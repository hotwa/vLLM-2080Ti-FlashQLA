#!/usr/bin/env bash
set -euo pipefail

script_dir="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)"
project_dir="$(CDPATH= cd -- "${script_dir}/.." && pwd)"

source "$script_dir/common.sh"
load_env_sources
setup_logging "$(basename "$0" .sh)"

ensure_venv

model_repo="${MODEL_REPO:-unsloth/Qwen3.6-35B-A3B-GGUF}"
model_file="${MODEL_FILE:-Qwen3.6-35B-A3B-Opus-Q5_K_M.gguf}"
model_dir="${MODEL_DIR:-./models/gguf}"
results_file="${RESULTS_DIR:-./results}/download_report.md"

mkdir -p "$project_dir/$model_dir" "$project_dir/${RESULTS_DIR:-./results}"

token="$(resolve_hf_token 2>/dev/null || true)"
token_source="anonymous"
if [ -n "$token" ]; then
  token_source="$(resolve_hf_token_source 2>/dev/null || printf '%s' 'unknown')"
fi

printf 'Model repo: %s\n' "$model_repo"
printf 'Target file: %s\n' "$model_file"
printf 'Local dir: %s\n' "$project_dir/$model_dir"
printf 'Token source: %s\n' "$token_source"

HF_DOWNLOAD_TOKEN="$token" \
"$project_dir/.venv/bin/python" - "$model_repo" "$model_file" "$project_dir/$model_dir" "$results_file" "$token_source" <<'PY'
from __future__ import annotations

import hashlib
import json
import os
from pathlib import Path
import sys

from huggingface_hub import hf_hub_download
from huggingface_hub.utils import HfHubHTTPError

repo_id = sys.argv[1]
filename = sys.argv[2]
local_dir = Path(sys.argv[3])
report_file = Path(sys.argv[4])
token_source = sys.argv[5]
token = os.environ.get("HF_DOWNLOAD_TOKEN") or None

local_dir.mkdir(parents=True, exist_ok=True)

auth_mode = "anonymous"
try:
    downloaded_path = Path(
        hf_hub_download(
            repo_id=repo_id,
            filename=filename,
            local_dir=local_dir,
            local_dir_use_symlinks=False,
            token=token,
            resume_download=True,
        )
    )
    if token:
        auth_mode = "authenticated"
except HfHubHTTPError as exc:
    message = str(exc)
    if "401" in message or "403" in message:
        raise SystemExit(
            "The Hugging Face repo is gated and no usable token was found. "
            "Set HF_TOKEN in the environment or create a local .env."
        ) from exc
    raise

if downloaded_path.suffix != ".gguf":
    raise SystemExit(f"Unexpected file extension: {downloaded_path}")

data = downloaded_path.read_bytes()
if len(data) < 16:
    raise SystemExit(f"Downloaded file is suspiciously small: {downloaded_path}")
if data[:4] != b"GGUF":
    raise SystemExit(f"Downloaded file does not look like GGUF: {downloaded_path}")

sha256 = hashlib.sha256(data).hexdigest()
size_bytes = len(data)

report_file.parent.mkdir(parents=True, exist_ok=True)
report_file.write_text(
    "\n".join(
        [
            "# Download Report",
            "",
            f"- Repo: `{repo_id}`",
            f"- File: `{filename}`",
            f"- Local path: `{downloaded_path}`",
            f"- Token source: `{token_source}`",
            f"- Auth mode: `{auth_mode}`",
            f"- Size: `{size_bytes}` bytes",
            f"- Sha256: `{sha256}`",
            f"- GGUF magic: `{data[:4].decode('ascii', 'ignore')}`",
            "",
        ]
    ),
    encoding="utf-8",
)

print(json.dumps(
    {
        "repo_id": repo_id,
        "filename": filename,
        "downloaded_path": str(downloaded_path),
        "token_source": token_source,
        "auth_mode": auth_mode,
        "size_bytes": size_bytes,
        "sha256": sha256,
    },
    indent=2,
))
PY
