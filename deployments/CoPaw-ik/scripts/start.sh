#!/usr/bin/env bash
set -euo pipefail

script_dir="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)"
project_dir="$(CDPATH= cd -- "${script_dir}/.." && pwd)"

cd "$project_dir"

gguf_basename="${GGUF_BASENAME:-CoPaw-Flash-9B-DataAnalyst-Merged}"
gguf_quant="${GGUF_QUANT:-Q5_K_M}"
gguf_quant_suffix="$(printf '%s' "$gguf_quant" | tr '[:upper:]' '[:lower:]')"

is_valid_gguf() {
  local candidate="$1"

  [ -n "$candidate" ] || return 1
  [ -f "$candidate" ] || return 1

  local magic
  magic="$(dd if="$candidate" bs=4 count=1 status=none 2>/dev/null | tr -d '\000' || true)"
  [ "$magic" = "GGUF" ]
}

resolve_model_file() {
  local candidates=()
  local candidate

  if [ -n "${MODEL_FILE:-}" ]; then
    candidates+=("$MODEL_FILE")
  fi

  candidates+=(
    "./models/gguf/${gguf_basename}-${gguf_quant_suffix}.gguf"
    "./models/gguf/${gguf_basename}-q4_k_s.gguf"
    "./models/gguf/${gguf_basename}-f16.gguf"
    "./models/gguf/test-qwen35.gguf"
  )

  for candidate in "${candidates[@]}"; do
    if is_valid_gguf "$candidate"; then
      printf '%s\n' "$candidate"
      return 0
    fi
  done

  return 1
}

model_file="$(resolve_model_file)" || {
  echo "No valid GGUF model file found." >&2
  echo "Expected one of:" >&2
  echo "  ./models/gguf/${gguf_basename}-${gguf_quant_suffix}.gguf" >&2
  echo "  ./models/gguf/${gguf_basename}-q4_k_s.gguf" >&2
  echo "  ./models/gguf/${gguf_basename}-f16.gguf" >&2
  echo "  ./models/gguf/test-qwen35.gguf" >&2
  exit 1
}

export MODEL_FILE="$model_file"
echo "Using GGUF model file: $MODEL_FILE"

server_image="copaw-ik-server:${IK_LLAMA_REF:-64234e3c4ea9c3cd2dd1a4f84c7da38e9607c747}"
if docker image inspect "$server_image" >/dev/null 2>&1; then
  compose_args=(up -d --no-build server)
else
  compose_args=(up -d --build server)
fi

docker compose "${compose_args[@]}"

cat <<EOF
Server started.

Next commands:
  docker compose logs -f server
  ./scripts/healthcheck.sh
  ./scripts/test_model.sh
  docker compose down
EOF
