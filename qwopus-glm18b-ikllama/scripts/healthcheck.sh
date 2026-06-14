#!/usr/bin/env bash
set -euo pipefail

script_dir="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)"
project_dir="$(CDPATH= cd -- "${script_dir}/.." && pwd)"

source "$script_dir/common.sh"
load_env_sources

require_command curl
cd "$project_dir"

container_id_file="$(runtime_container_file)"
pid_file="$(runtime_pid_file)"
container_id=""
if [ -s "$container_id_file" ]; then
  container_id="$(cat "$container_id_file")"
elif [ -s "$pid_file" ]; then
  container_id="$(cat "$pid_file")"
fi

if [ -z "$container_id" ]; then
  die "No runtime marker found. Start the server first."
fi

if ! docker_cmd inspect "$container_id" >/dev/null 2>&1; then
  die "Container not found: $container_id"
fi

running="$(docker_cmd inspect -f '{{.State.Running}}' "$container_id" 2>/dev/null || echo false)"
if [ "$running" != "true" ]; then
  die "Container is not running: $container_id"
fi

port="${PORT:-8080}"
url="http://127.0.0.1:${port}/v1/models"
api_key="${API_KEY:-}"

if ! wait_for_http "$url" 10 1 "$api_key"; then
  die "Port ${port} is not responding on /v1/models"
fi

printf 'OK: container=%s port=%s /v1/models=up\n' "$container_id" "$port"
