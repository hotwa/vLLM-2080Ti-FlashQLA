#!/usr/bin/env python3
from __future__ import annotations

import argparse
import hashlib
import os
from datetime import datetime, timezone
from pathlib import Path
import tempfile

from huggingface_hub import HfApi


PROJECT_ROOT = Path(os.environ.get("PROJECT_ROOT", Path(__file__).resolve().parents[1])).resolve()
MODEL_DIR = PROJECT_ROOT / "models" / "gguf"
RESULTS_DIR = PROJECT_ROOT / "results"

PUBLISH_FILES = [
    "CoPaw-Flash-9B-DataAnalyst-Merged-f16.gguf",
    "CoPaw-Flash-9B-DataAnalyst-Merged-q5_k_m.gguf",
    "CoPaw-Flash-9B-DataAnalyst-Merged-q4_k_s.gguf",
]


def resolve_token() -> tuple[str, str]:
    for name in ("HF_TOKEN", "HUGGINGFACE_TOKEN", "HUGGING_FACE_HUB_TOKEN"):
        value = os.environ.get(name, "").strip()
        if value:
            return value, name
    raise SystemExit(
        "No Hugging Face token found. Set HF_TOKEN, HUGGINGFACE_TOKEN, or HUGGING_FACE_HUB_TOKEN."
    )


def read_gguf(path: Path) -> dict[str, str | int]:
    data = path.read_bytes()
    if len(data) < 16:
        raise SystemExit(f"GGUF file is too small: {path}")
    if data[:4] != b"GGUF":
        raise SystemExit(f"GGUF magic missing for: {path}")
    return {
        "name": path.name,
        "size_bytes": len(data),
        "sha256": hashlib.sha256(data).hexdigest(),
    }


def render_model_card(repo_id: str, entries: list[dict[str, str | int]]) -> str:
    lines = [
        "---",
        "license: apache-2.0",
        "tags:",
        "- gguf",
        "- ik_llama.cpp",
        "- copaw",
        "- quantized-llm",
        "---",
        "",
        "# CoPaw-Flash-9B-DataAnalyst GGUF",
        "",
        "Merged CoPaw GGUF variants for local inference and sharing.",
        "",
        f"Repository: `{repo_id}`",
        "",
        "## Files",
        "",
    ]
    for entry in entries:
        lines.append(f"- `{entry['name']}`")
    lines += [
        "",
        "## Notes",
        "",
        "- `Q5_K_M` is the preferred publish artifact.",
        "- `Q4_K_S` is the lighter alternative.",
        "- `f16` is the baseline reference file.",
        "- The files were generated from the merged CoPaw deployment in this workspace.",
        "",
    ]
    return "\n".join(lines)


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--repo", required=True)
    args = parser.parse_args()

    token, token_source = resolve_token()
    api = HfApi(token=token)

    repo_id = args.repo
    api.create_repo(repo_id=repo_id, repo_type="model", exist_ok=True)

    files = []
    for filename in PUBLISH_FILES:
        path = MODEL_DIR / filename
        if not path.exists():
            raise SystemExit(f"Missing publish artifact: {path}")
        files.append(read_gguf(path))

    with tempfile.TemporaryDirectory() as tmpdir:
        tmpdir_path = Path(tmpdir)
        readme_path = tmpdir_path / "README.md"
        readme_path.write_text(render_model_card(repo_id, files), encoding="utf-8")
        api.upload_file(
            path_or_fileobj=str(readme_path),
            path_in_repo="README.md",
            repo_id=repo_id,
            repo_type="model",
            commit_message="Add model card",
        )

        for filename in PUBLISH_FILES:
            path = MODEL_DIR / filename
            api.upload_file(
                path_or_fileobj=str(path),
                path_in_repo=filename,
                repo_id=repo_id,
                repo_type="model",
                commit_message=f"Upload {filename}",
            )

    RESULTS_DIR.mkdir(parents=True, exist_ok=True)
    report = RESULTS_DIR / "publish_report.md"
    report.write_text(
        "\n".join(
            [
                "# CoPaw HF Publish Report",
                "",
                f"- Repo: `{repo_id}`",
                f"- Token source: `{token_source}`",
                f"- Published at: `{datetime.now(timezone.utc).isoformat()}`",
                "",
                "## Files",
                "",
            ]
            + [
                f"- `{entry['name']}` | `{entry['size_bytes']}` bytes | `{entry['sha256']}`"
                for entry in files
            ]
            + [""]
        ),
        encoding="utf-8",
    )

    print(report.read_text(encoding="utf-8"))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
