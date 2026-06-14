#!/usr/bin/env python3
from __future__ import annotations

import csv
import datetime as dt
import json
import os
import subprocess
import threading
import time
import urllib.error
import urllib.request
from pathlib import Path
from typing import Any


PROJECT_ROOT = Path(__file__).resolve().parents[1]
RESULTS_DIR = Path(os.environ.get("RESULTS_DIR", PROJECT_ROOT / "results"))
LOG_DIR = Path(os.environ.get("LOG_DIR", PROJECT_ROOT / "logs"))
ARTIFACT_DIR = Path(os.environ.get("ARTIFACT_DIR", PROJECT_ROOT / "artifacts"))
PROMPT_DIR = ARTIFACT_DIR / "prompts"
RAW_CSV = RESULTS_DIR / "benchmark_raw.csv"
SUMMARY_MD = RESULTS_DIR / "benchmark_summary.md"
SYSTEM_INFO = RESULTS_DIR / "system_info.md"

MODEL_NAME = os.environ.get("MODEL_NAME", "Qwen3.6-35B-A3B-UD-Q5_K_M")
HOST_PORT = int(os.environ.get("HOST_PORT", "8000"))
BASE_URL = os.environ.get("BENCHMARK_BASE_URL", f"http://127.0.0.1:{HOST_PORT}/v1")
CONTEXTS = [
    int(part.strip())
    for part in os.environ.get("BENCHMARK_CONTEXTS", "16384,32768,65536").split(",")
    if part.strip()
]
MAX_NEW_TOKENS = int(os.environ.get("BENCHMARK_MAX_NEW_TOKENS", "256"))
RESERVE_TOKENS = int(os.environ.get("BENCHMARK_RESERVE_TOKENS", "1024"))
REQUEST_TIMEOUT = float(os.environ.get("BENCHMARK_REQUEST_TIMEOUT", "1800"))
HEALTH_TIMEOUT = float(os.environ.get("BENCHMARK_HEALTH_TIMEOUT", "1800"))
HEALTH_INTERVAL = float(os.environ.get("BENCHMARK_HEALTH_INTERVAL", "10"))
GPU_SAMPLE_INTERVAL = float(os.environ.get("BENCHMARK_GPU_SAMPLE_INTERVAL", "0.25"))
PROFILE_NAME = os.environ.get("BENCHMARK_PROFILE", "stable")
PROFILE_FILE = Path(os.environ.get("BENCHMARK_PROFILE_FILE", PROJECT_ROOT / "configs" / "profiles.json"))


def run_cmd(args: list[str], *, env: dict[str, str] | None = None, check: bool = True) -> subprocess.CompletedProcess[str]:
    return subprocess.run(
        args,
        cwd=PROJECT_ROOT,
        env=env,
        check=check,
        capture_output=True,
        text=True,
    )


def load_profile(name: str) -> dict[str, str]:
    if PROFILE_FILE.exists():
        payload = json.loads(PROFILE_FILE.read_text(encoding="utf-8"))
        if name not in payload:
            raise SystemExit(f"Unknown benchmark profile: {name}")
        return {key: str(value) for key, value in payload[name].items()}
    return {}


def compose_env(context_len: int) -> dict[str, str]:
    env = os.environ.copy()
    env.update(load_profile(PROFILE_NAME))
    env["MAX_MODEL_LEN"] = str(context_len)
    env["MODEL_NAME"] = MODEL_NAME
    env["HOST_PORT"] = str(HOST_PORT)
    env["RESULTS_DIR"] = str(RESULTS_DIR)
    env["LOG_DIR"] = str(LOG_DIR)
    env["ARTIFACT_DIR"] = str(ARTIFACT_DIR)
    return env


def ensure_dirs() -> None:
    RESULTS_DIR.mkdir(parents=True, exist_ok=True)
    LOG_DIR.mkdir(parents=True, exist_ok=True)
    PROMPT_DIR.mkdir(parents=True, exist_ok=True)


def wait_for_health(env: dict[str, str]) -> None:
    deadline = time.monotonic() + HEALTH_TIMEOUT
    last_error = ""

    while time.monotonic() < deadline:
        result = run_cmd(["./scripts/healthcheck.sh"], env=env, check=False)
        if result.returncode == 0:
            return
        last_error = (result.stdout + result.stderr).strip()
        time.sleep(HEALTH_INTERVAL)

    raise RuntimeError(last_error or "service did not become healthy in time")


def start_service(env: dict[str, str], context_len: int) -> None:
    print(f"[ctx={context_len}] starting service")
    run_cmd(["./scripts/start.sh"], env=env)
    wait_for_health(env)


def stop_service() -> None:
    run_cmd(["./scripts/stop.sh"], check=False)


class PeakMemorySampler:
    def __init__(self, interval: float) -> None:
        self.interval = interval
        self.peak_mib: int | None = None
        self._stop = threading.Event()
        self._thread = threading.Thread(target=self._run, daemon=True)

    def _run(self) -> None:
        while not self._stop.is_set():
            try:
                result = run_cmd(
                    [
                        "nvidia-smi",
                        "--query-gpu=memory.used",
                        "--format=csv,noheader,nounits",
                    ],
                    check=False,
                )
                samples = [
                    int(line.strip())
                    for line in result.stdout.splitlines()
                    if line.strip().isdigit()
                ]
                if samples:
                    peak = max(samples)
                    if self.peak_mib is None or peak > self.peak_mib:
                        self.peak_mib = peak
            except Exception:
                pass
            self._stop.wait(self.interval)

    def start(self) -> None:
        self._thread.start()

    def stop(self) -> None:
        self._stop.set()
        self._thread.join(timeout=max(self.interval * 4, 1.0))


def build_prompt(context_len: int) -> str:
    prompt_path = PROMPT_DIR / f"{context_len}.txt"
    run_cmd(
        [
            "python3",
            "scripts/generate_prompt.py",
            "--target-context",
            str(context_len),
            "--max-new-tokens",
            str(MAX_NEW_TOKENS),
            "--reserve-tokens",
            str(RESERVE_TOKENS),
            "--output",
            str(prompt_path),
        ],
        env=os.environ.copy(),
    )
    return prompt_path.read_text(encoding="utf-8")


def stream_request(prompt: str, env: dict[str, str]) -> dict[str, Any]:
    payload = {
        "model": MODEL_NAME,
        "messages": [{"role": "user", "content": prompt}],
        "temperature": 0.0,
        "max_tokens": MAX_NEW_TOKENS,
        "stream": True,
        "stream_options": {"include_usage": True},
    }
    request = urllib.request.Request(
        f"{BASE_URL}/chat/completions",
        data=json.dumps(payload).encode("utf-8"),
        headers={"Content-Type": "application/json"},
        method="POST",
    )

    sampler = PeakMemorySampler(GPU_SAMPLE_INTERVAL)
    sampler.start()
    started = time.perf_counter()
    first_token_at: float | None = None
    output_parts: list[str] = []
    final_usage: dict[str, Any] | None = None
    error: str | None = None

    try:
        with urllib.request.urlopen(request, timeout=REQUEST_TIMEOUT) as response:
            for raw_line in response:
                line = raw_line.decode("utf-8", "replace").strip()
                if not line.startswith("data: "):
                    continue
                event_text = line[6:]
                if event_text == "[DONE]":
                    break
                event = json.loads(event_text)
                choices = event.get("choices") or []
                if choices:
                    delta = choices[0].get("delta") or {}
                    chunk = delta.get("content")
                    if chunk:
                        output_parts.append(chunk)
                        if first_token_at is None:
                            first_token_at = time.perf_counter()
                usage = event.get("usage")
                if isinstance(usage, dict):
                    final_usage = usage
    except urllib.error.HTTPError as exc:
        error = f"HTTP {exc.code}: {exc.read().decode('utf-8', 'replace')}"
    except urllib.error.URLError as exc:
        error = f"URL error: {exc.reason}"
    except Exception as exc:
        error = f"{type(exc).__name__}: {exc}"
    finally:
        ended = time.perf_counter()
        sampler.stop()

    if error is not None:
        return {
            "status": "error",
            "error": error,
            "peak_vram_mib": sampler.peak_mib,
        }

    if first_token_at is None:
        first_token_at = ended

    prompt_tokens = None
    completion_tokens = None
    total_tokens = None
    if isinstance(final_usage, dict):
        prompt_tokens = final_usage.get("prompt_tokens")
        completion_tokens = final_usage.get("completion_tokens")
        total_tokens = final_usage.get("total_tokens")

    if prompt_tokens is None:
        prompt_tokens = tokenize_via_server(render_chat_prompt(prompt))
    if completion_tokens is None:
        completion_tokens = tokenize_via_server("".join(output_parts))
    if total_tokens is None and prompt_tokens is not None and completion_tokens is not None:
        total_tokens = int(prompt_tokens) + int(completion_tokens)

    ttft_s = first_token_at - started
    decode_s = max(ended - first_token_at, 1e-9)
    prompt_processing_tok_s = (
        prompt_tokens / ttft_s if isinstance(prompt_tokens, int) and ttft_s > 0 else None
    )
    decode_tok_s = (
        completion_tokens / decode_s if isinstance(completion_tokens, int) else None
    )

    return {
        "status": "ok",
        "error": "",
        "prompt_tokens": prompt_tokens,
        "completion_tokens": completion_tokens,
        "total_tokens": total_tokens,
        "ttft_s": ttft_s,
        "prompt_processing_tok_s": prompt_processing_tok_s,
        "decode_tok_s": decode_tok_s,
        "peak_vram_mib": sampler.peak_mib,
        "output_text": "".join(output_parts),
    }


def tokenize_via_server(text: str) -> int | None:
    payload = json.dumps({"content": text}).encode("utf-8")
    request = urllib.request.Request(
        f"{BASE_URL}/tokenize",
        data=payload,
        headers={"Content-Type": "application/json"},
        method="POST",
    )
    try:
        with urllib.request.urlopen(request, timeout=REQUEST_TIMEOUT) as response:
            data = json.loads(response.read().decode("utf-8", "replace"))
        tokens = data.get("tokens")
        if isinstance(tokens, list):
            return len(tokens)
    except Exception:
        return None
    return None


def render_chat_prompt(user_content: str) -> str:
    return (
        "<|im_start|>user\n"
        f"{user_content}"
        "<|im_end|>\n"
        "<|im_start|>assistant\n"
    )


def write_raw_csv(rows: list[dict[str, Any]]) -> None:
    with RAW_CSV.open("w", encoding="utf-8", newline="") as fh:
        writer = csv.DictWriter(
            fh,
            fieldnames=[
                "profile",
                "context_len",
                "prompt_tokens",
                "completion_tokens",
                "total_tokens",
                "ttft_s",
                "prompt_processing_tok_s",
                "decode_tok_s",
                "peak_vram_mib",
                "status",
                "error",
            ],
        )
        writer.writeheader()
        for row in rows:
            writer.writerow({key: row.get(key) for key in writer.fieldnames})


def fmt(value: Any) -> str:
    if value is None:
        return ""
    if isinstance(value, float):
        return f"{value:.3f}"
    return str(value).replace("|", "\\|").replace("\n", "<br>")


def write_summary(rows: list[dict[str, Any]]) -> None:
    baseline = next((row for row in rows if int(row["context_len"]) == min(CONTEXTS) and row["status"] == "ok"), None)
    lines = [
        "# Benchmark Summary",
        "",
        f"- Generated: {dt.datetime.now().astimezone().isoformat(timespec='seconds')}",
        f"- Profile: `{PROFILE_NAME}`",
        f"- Model: `{MODEL_NAME}`",
        "",
        "| Context | Prompt tokens | Completion tokens | TTFT (s) | Prompt proc tok/s | Decode tok/s | Peak VRAM (MiB) | Status |",
        "|---:|---:|---:|---:|---:|---:|---:|---|",
    ]

    for row in rows:
        lines.append(
            "| "
            + " | ".join(
                [
                    fmt(row["context_len"]),
                    fmt(row["prompt_tokens"]),
                    fmt(row["completion_tokens"]),
                    fmt(row["ttft_s"]),
                    fmt(row["prompt_processing_tok_s"]),
                    fmt(row["decode_tok_s"]),
                    fmt(row["peak_vram_mib"]),
                    fmt(row["status"]),
                ]
            )
            + " |"
        )

    if baseline and isinstance(baseline.get("decode_tok_s"), (int, float)) and isinstance(baseline.get("prompt_processing_tok_s"), (int, float)):
        lines.extend(
            [
                "",
                "## Decay vs 16k baseline",
                "",
                "| Context | Prompt proc ratio | Decode ratio | TTFT multiplier |",
                "|---:|---:|---:|---:|",
            ]
        )
        base_prompt = float(baseline["prompt_processing_tok_s"])
        base_decode = float(baseline["decode_tok_s"])
        base_ttft = float(baseline["ttft_s"])
        for row in rows:
            if row["status"] != "ok":
                continue
            lines.append(
                "| "
                + " | ".join(
                    [
                        fmt(row["context_len"]),
                        fmt(float(row["prompt_processing_tok_s"]) / base_prompt if row.get("prompt_processing_tok_s") else None),
                        fmt(float(row["decode_tok_s"]) / base_decode if row.get("decode_tok_s") else None),
                        fmt(float(row["ttft_s"]) / base_ttft if row.get("ttft_s") else None),
                    ]
                )
                + " |"
            )

    SUMMARY_MD.write_text("\n".join(lines) + "\n", encoding="utf-8")


def benchmark() -> int:
    ensure_dirs()
    if not SYSTEM_INFO.exists():
        run_cmd(["./scripts/collect_system_info.sh"], env=os.environ.copy())

    rows: list[dict[str, Any]] = []
    failures = 0

    try:
        for context_len in CONTEXTS:
            env = compose_env(context_len)
            row: dict[str, Any] = {
                "profile": PROFILE_NAME,
                "context_len": context_len,
                "prompt_tokens": None,
                "completion_tokens": None,
                "ttft_s": None,
                "prompt_processing_tok_s": None,
                "decode_tok_s": None,
                "peak_vram_mib": None,
                "status": "error",
                "error": "",
            }

            try:
                start_service(env, context_len)
                prompt = build_prompt(context_len)
                result = stream_request(prompt, env)
                row.update(result)
                if result.get("status") != "ok":
                    failures += 1
                else:
                    print(
                        f"[ctx={context_len}] prompt={result.get('prompt_tokens')} "
                        f"completion={result.get('completion_tokens')} "
                        f"ttft={result.get('ttft_s'):.3f}s "
                        f"prompt_proc={result.get('prompt_processing_tok_s'):.3f} tok/s "
                        f"decode={result.get('decode_tok_s'):.3f} tok/s "
                        f"peak_vram={result.get('peak_vram_mib')} MiB"
                    )
            except Exception as exc:
                failures += 1
                row["error"] = f"{type(exc).__name__}: {exc}"
                print(f"[ctx={context_len}] failed: {row['error']}")
            finally:
                rows.append(row)
                write_raw_csv(rows)
                stop_service()
    finally:
        stop_service()

    write_summary(rows)
    print(f"Benchmark summary written to {SUMMARY_MD}")
    print(f"Raw CSV written to {RAW_CSV}")
    return 1 if failures else 0


if __name__ == "__main__":
    raise SystemExit(benchmark())
