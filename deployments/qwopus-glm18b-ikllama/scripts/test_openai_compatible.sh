#!/usr/bin/env bash
set -euo pipefail

script_dir="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)"
project_dir="$(CDPATH= cd -- "${script_dir}/.." && pwd)"

source "$script_dir/common.sh"
load_env_sources

require_command curl
require_command jq

port="${PORT:-8080}"
base_url="http://127.0.0.1:${port}/v1"
auth_args=()
if [ -n "${API_KEY:-}" ]; then
  auth_args=(-H "Authorization: Bearer ${API_KEY}")
fi

models_response="$(mktemp)"
chat_response="$(mktemp)"
cleanup() {
  rm -f "$models_response" "$chat_response"
}
trap cleanup EXIT

if ! curl -fsS "${auth_args[@]}" "$base_url/models" >"$models_response"; then
  die "Failed to fetch $base_url/models. Is the server running?"
fi

model_name="$(jq -r '.data[0].id // empty' "$models_response")"
if [ -z "$model_name" ] || [ "$model_name" = "null" ]; then
  model_name="${MODEL_NAME:-$(model_alias_from_path "$(resolve_host_path "${MODEL_PATH:-./models/Qwopus-GLM-18B-Healed-Q4_K_M.gguf}")")}"
fi

request_body="$(jq -n \
  --arg model "$model_name" \
  '{
    model: $model,
    messages: [
      {
        role: "user",
        content: "请用中文回复：你好，简要介绍一下你自己。"
      }
    ],
    temperature: 0.7,
    max_tokens: 64,
    stream: false
  }')"

if ! curl -fsS \
  -H 'Content-Type: application/json' \
  "${auth_args[@]}" \
  -d "$request_body" \
  "$base_url/chat/completions" >"$chat_response"; then
  printf 'Chat completion request failed.\n' >&2
  printf 'Common checks:\n' >&2
  printf '  - run ./scripts/healthcheck.sh\n' >&2
  printf '  - inspect logs at %s\n' "$(runtime_log_file)" >&2
  printf '  - confirm MODEL_PATH points to the downloaded GGUF\n' >&2
  printf '  - lower CTX_SIZE if the server cannot start\n' >&2
  exit 1
fi

jq '.' "$chat_response"
printf '\nAssistant reply:\n'
jq -r '.choices[0].message.content // empty' "$chat_response"
