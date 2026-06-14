#!/usr/bin/env bash
set -euo pipefail

script_dir="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)"
project_dir="$(CDPATH= cd -- "${script_dir}/.." && pwd)"

cd "$project_dir"

source_model="${BASE_MODEL_SOURCE:-../CoPaw/models/base/CoPaw-Flash-9B}"
lora_model="${LORA_SOURCE:-../CoPaw/models/lora/CoPaw-Flash-9B-DataAnalyst-LoRA}"

if [ -f "${source_model}/model.safetensors" ] && [ -f "${lora_model}/adapter_model.safetensors" ]; then
  echo "Source base model and LoRA adapter are already present."
  echo "Base: ${source_model}"
  echo "LoRA: ${lora_model}"
  exit 0
fi

docker compose run --rm tools bash -lc '
  set -euo pipefail

  download_repo() {
    repo_id="$1"
    target_dir="$2"

    mkdir -p "$target_dir"

    if command -v huggingface-cli >/dev/null 2>&1; then
      huggingface-cli download "$repo_id" \
        --local-dir "$target_dir" \
        --local-dir-use-symlinks False
      return
    fi

    if command -v hf >/dev/null 2>&1; then
      hf download "$repo_id" \
        --local-dir "$target_dir" \
        --local-dir-use-symlinks False
      return
    fi

    python3 - "$repo_id" "$target_dir" <<'"'"'PY'"'"'
import sys
from huggingface_hub import snapshot_download

repo_id = sys.argv[1]
target_dir = sys.argv[2]

snapshot_download(
    repo_id=repo_id,
    local_dir=target_dir,
    local_dir_use_symlinks=False,
)
PY
  }

  base_repo="${BASE_MODEL_REPO:-agentscope-ai/CoPaw-Flash-9B}"
  lora_repo="${LORA_REPO:-jason1966/CoPaw-Flash-9B-DataAnalyst-LoRA}"
  base_target="/source/CoPaw/models/base/CoPaw-Flash-9B"
  lora_target="/source/CoPaw/models/lora/CoPaw-Flash-9B-DataAnalyst-LoRA"

  if [ ! -f "$base_target/model.safetensors" ]; then
    echo "Downloading base model: $base_repo"
    download_repo "$base_repo" "$base_target"
  fi

  if [ ! -f "$lora_target/adapter_model.safetensors" ]; then
    echo "Downloading LoRA adapter: $lora_repo"
    download_repo "$lora_repo" "$lora_target"
  fi

  echo "Download check complete."
  echo "Base model: $base_target"
  echo "LoRA adapter: $lora_target"
'
