#!/usr/bin/env bash
set -euo pipefail

script_dir="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)"
project_dir="$(CDPATH= cd -- "${script_dir}/.." && pwd)"

source "$script_dir/common.sh"
load_env_sources
ensure_project_dirs

require_command python3
require_command curl

target_dir="$project_dir/models"
repo_id="${MODEL_REPO:-Jackrong/Qwopus-GLM-18B-Merged-GGUF}"
filename="${MODEL_FILENAME:-Qwopus-GLM-18B-Healed-Q4_K_M.gguf}"
target_path="$target_dir/$filename"

if [ -f "$target_path" ]; then
  size_bytes="$(stat -c '%s' "$target_path")"
  if [ "$size_bytes" -gt 1073741824 ]; then
    printf 'Model already exists: %s (%s bytes)\n' "$target_path" "$size_bytes"
    exit 0
  fi
  die "Existing model file is too small: $target_path (${size_bytes} bytes)"
fi

if ! python3 -m pip show huggingface_hub >/dev/null 2>&1; then
  printf 'Installing huggingface_hub for the current user...\n'
  python3 -m pip install --user --upgrade huggingface_hub
fi

token="${HF_TOKEN:-}"

python3 - "$repo_id" "$filename" "$target_path" "${token:-}" <<'PY'
from __future__ import annotations

import os
import sys
from pathlib import Path

from huggingface_hub import hf_hub_download

repo_id = sys.argv[1]
filename = sys.argv[2]
target_path = Path(sys.argv[3])
token = sys.argv[4] or None

target_path.parent.mkdir(parents=True, exist_ok=True)

downloaded = Path(
    hf_hub_download(
        repo_id=repo_id,
        filename=filename,
        local_dir=target_path.parent,
        local_dir_use_symlinks=False,
        resume_download=True,
        token=token,
    )
)

if not downloaded.exists():
    raise SystemExit(f"Download did not produce a file: {downloaded}")

size_bytes = downloaded.stat().st_size
if size_bytes <= 1_073_741_824:
    raise SystemExit(f"Downloaded file is too small: {downloaded} ({size_bytes} bytes)")

with downloaded.open("rb") as fh:
    magic = fh.read(4)

if magic != b"GGUF":
    raise SystemExit(f"Downloaded file does not look like GGUF: {downloaded}")

print(f"Downloaded: {downloaded}")
print(f"Size: {size_bytes} bytes")
PY

