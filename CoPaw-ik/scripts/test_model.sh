#!/usr/bin/env bash
set -euo pipefail

script_dir="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)"
project_dir="$(CDPATH= cd -- "${script_dir}/.." && pwd)"

cd "$project_dir"

host_port="${HOST_PORT:-8000}"
model_name="${MODEL_NAME:-CoPaw-Flash-9B-DataAnalyst-Merged}"

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
  "max_tokens": 64,
  "temperature": 0.2
}
EOF
)"

python3 - "$response" <<'PY'
import json
import sys

data = json.loads(sys.argv[1])
choice = data["choices"][0]
message = choice.get("message", {})
content = message.get("content")
reasoning = message.get("reasoning_content")

print("Chat completion succeeded.")
print(f"content: {content!r}")
if reasoning is not None:
    print(f"reasoning_content: {reasoning!r}")
PY
