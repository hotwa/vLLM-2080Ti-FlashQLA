#!/usr/bin/env bash
set -euo pipefail

COMPOSE_FILE="${COMPOSE_FILE:-qwen/docker-compose.2080ti-ik-main-262k.yml}"
CONTAINER="${CONTAINER:-qwen36-27b-ik-main-262k}"
PORT="${QWEN_IK_MAIN_HOST_PORT:-8080}"
MODEL="${MODEL_ALIAS:-Qwen3.6-27B}"

docker compose -f "$COMPOSE_FILE" build
docker compose -f "$COMPOSE_FILE" up -d

echo "[INFO] Waiting for health endpoint on port ${PORT}"
for _ in $(seq 1 360); do
    if curl -fsS "http://127.0.0.1:${PORT}/health" >/dev/null 2>&1; then
        break
    fi
    docker ps --filter "name=${CONTAINER}" --format '{{.Names}} {{.Status}}'
    sleep 2
done

curl -fsS "http://127.0.0.1:${PORT}/health"
echo
curl -fsS "http://127.0.0.1:${PORT}/v1/models" | jq

curl -s "http://127.0.0.1:${PORT}/v1/chat/completions" \
  -H "Content-Type: application/json" \
  -d "$(jq -nc --arg model "$MODEL" '{
    model: $model,
    messages: [
      {role: "user", content: "Write a concise Python binary search function, no explanation."}
    ],
    temperature: 0.2,
    max_tokens: 256,
    stop: ["<|im_end|>", "<|endoftext|>"]
  }')" | jq

echo "[INFO] Logs:"
docker logs --tail 80 "$CONTAINER"
