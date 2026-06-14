#!/usr/bin/env bash
set -euo pipefail

log_file="/workspace/logs/llama-server.log"
mkdir -p /workspace/logs /workspace/run
: > "$log_file"

resolve_container_path() {
  local input="${1:-}"
  if [ -z "$input" ]; then
    return 1
  fi
  if [ "${input#./}" != "$input" ]; then
    printf '/workspace/%s\n' "${input#./}"
    return 0
  fi
  case "$input" in
    /*) printf '%s\n' "$input" ;;
    *) printf '/workspace/%s\n' "$input" ;;
  esac
}

model_path="$(resolve_container_path "${MODEL_PATH:-}")"
if [ ! -f "$model_path" ]; then
  echo "Missing model file: $model_path" >&2
  echo "Run ./scripts/download_model.sh first." >&2
  exit 1
fi

model_name="${MODEL_NAME:-}"
if [ -z "$model_name" ]; then
  model_name="$(basename "$model_path")"
  model_name="${model_name%.gguf}"
fi

ctx_size="${CTX_SIZE:-65536}"
gpu_layers="${GPU_LAYERS:-999}"
batch_size="${BATCH_SIZE:-2048}"
ubatch_size="${UBATCH_SIZE:-512}"
threads="${THREADS:-8}"
cache_type_k="${CACHE_TYPE_K:-q8_0}"
cache_type_v="${CACHE_TYPE_V:-q8_0}"
flash_attn="${FLASH_ATTN:-1}"
jinja="${JINJA:-0}"
chat_template_file="${CHAT_TEMPLATE_FILE:-}"
no_context_shift="${NO_CONTEXT_SHIFT:-1}"
no_mmap="${NO_MMAP:-1}"
split_mode="${SPLIT_MODE:-}"
tensor_split="${TENSOR_SPLIT:-}"
api_key="${API_KEY:-}"
host="${HOST:-0.0.0.0}"
port="${PORT:-8080}"
n_parallel="${N_PARALLEL:-1}"

cmd=(
  llama-server
  -m "$model_path"
  --alias "$model_name"
  --host "$host"
  --port "$port"
  -c "$ctx_size"
  -ngl "$gpu_layers"
  -b "$batch_size"
  -ub "$ubatch_size"
  -t "$threads"
  -np "$n_parallel"
  --cache-type-k "$cache_type_k"
  --cache-type-v "$cache_type_v"
)

if [ -n "$api_key" ]; then
  cmd+=(--api-key "$api_key")
fi

if [ -n "$split_mode" ] && [ "$split_mode" != "none" ]; then
  cmd+=(--split-mode "$split_mode")
fi

if [ -n "$tensor_split" ]; then
  cmd+=(--tensor-split "$tensor_split")
fi

if [ "$flash_attn" != "0" ] && llama-server --help 2>/dev/null | grep -q -- '--flash-attn'; then
  cmd+=(--flash-attn on)
fi

if [ "$jinja" = "1" ]; then
  cmd+=(--jinja)
fi

if [ "$jinja" = "1" ] && [ -n "$chat_template_file" ]; then
  cmd+=(--chat-template-file "$(resolve_container_path "$chat_template_file")")
fi

if [ "$no_context_shift" != "0" ]; then
  cmd+=(--no-context-shift)
fi

if [ "$no_mmap" != "0" ]; then
  cmd+=(--no-mmap)
fi

echo "Starting llama-server for model: $model_name"
echo "Model path: $model_path"
echo "Log file: $log_file"
echo "Full command: ${cmd[*]}"

# 使用 stdbuf 禁用输出缓冲，确保崩溃前的日志能写入文件
exec stdbuf -oL -eL "${cmd[@]}" >>"$log_file" 2>&1
