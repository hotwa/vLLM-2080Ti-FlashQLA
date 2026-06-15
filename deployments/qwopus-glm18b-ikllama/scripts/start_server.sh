#!/usr/bin/env bash
set -euo pipefail

script_dir="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)"
project_dir="$(CDPATH= cd -- "${script_dir}/.." && pwd)"

source "$script_dir/common.sh"

if [ ! -f "$project_dir/.env" ]; then
  die "Missing .env. Copy .env.example to .env and fill in any custom values."
fi

load_env_sources
ensure_project_dirs
cd "$project_dir"

require_command git
require_command curl
require_nvidia_gpu

model_path_host="$(resolve_host_path "${MODEL_PATH:-./models/Qwopus-GLM-18B-Healed-Q4_K_M.gguf}")"
if [ ! -f "$model_path_host" ]; then
  die "Model file not found: $model_path_host. Run ./scripts/download_model.sh first."
fi

if [ -d "$project_dir/repos/ik_llama.cpp/.git" ] && [ -n "$(git -C "$project_dir/repos/ik_llama.cpp" status --porcelain 2>/dev/null || true)" ]; then
  die "The repository at $project_dir/repos/ik_llama.cpp has local changes. Please clean it up before starting."
fi

"$script_dir/build_ik_llama.sh"

container_id_file="$(runtime_container_file)"
pid_file="$(runtime_pid_file)"
log_file="$(runtime_log_file)"
mkdir -p "$(runtime_dir)"

if [ -s "$container_id_file" ]; then
  existing_container_id="$(cat "$container_id_file")"
  if [ -n "$existing_container_id" ] && docker_cmd inspect "$existing_container_id" >/dev/null 2>&1; then
    if [ "$(docker_cmd inspect -f '{{.State.Running}}' "$existing_container_id" 2>/dev/null || echo false)" = "true" ]; then
      printf 'Server already running (container=%s).\n' "$existing_container_id"
      printf 'Log file: %s\n' "$log_file"
      exit 0
    fi
  fi
fi

printf 'Starting compose service...\n'
compose_cmd up -d server

container_id="$(compose_cmd ps -q server)"
if [ -z "$container_id" ]; then
  die "Compose did not return a container id."
fi

printf '%s\n' "$container_id" > "$container_id_file"
printf '%s\n' "$container_id" > "$pid_file"

service_port="${PORT:-8080}"
service_host="${HOST:-0.0.0.0}"
base_url="http://127.0.0.1:${service_port}"
api_key="${API_KEY:-}"

printf 'Waiting for service on %s ...\n' "$base_url"
if ! wait_for_http "$base_url/v1/models" 120 2 "$api_key"; then
  printf 'Service did not become ready in time.\n' >&2
  compose_cmd logs --no-color --tail 100 server >&2 || true
  exit 1
fi

printf 'Service URL: http://%s:%s\n' "$service_host" "$service_port"
printf 'OpenAI-compatible base URL: %s/v1\n' "$base_url"
printf 'Recommended model name: %s\n' "${MODEL_NAME:-$(model_alias_from_path "$model_path_host")}"
printf 'Log file: %s\n' "$log_file"
printf 'Container id: %s\n' "$container_id"
