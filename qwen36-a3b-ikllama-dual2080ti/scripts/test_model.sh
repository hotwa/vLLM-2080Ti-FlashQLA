#!/usr/bin/env bash
set -euo pipefail

script_dir="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)"
project_dir="$(CDPATH= cd -- "${script_dir}/.." && pwd)"

source "$script_dir/common.sh"
load_env_sources
setup_logging "$(basename "$0" .sh)"

host_port="${HOST_PORT:-8000}"
model_name="${MODEL_NAME:-Qwen3.6-35B-A3B-UD-Q5_K_M}"

response="$(
  curl -fsS "http://127.0.0.1:${host_port}/v1/chat/completions" \
    -H "Content-Type: application/json" \
    -d @- <<EOF
{
  "model": "${model_name}",
  "messages": [
    {
      "role": "user",
      "content": "Reply with exactly: ok"
    }
  ],
  "temperature": 0.0,
  "max_tokens": 32
}
EOF
)"

python3 - "$response" <<'PY'
import json
import sys

data = json.loads(sys.argv[1])
choice = data["choices"][0]
message = choice.get("message", {})
content = message.get("content", "")

print("Chat completion succeeded.")
print(f"content: {content!r}")
if not content.strip():
    raise SystemExit("Smoke test returned empty content.")
PY
