#!/usr/bin/env bash
set -euo pipefail

script_dir="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)"
project_dir="$(CDPATH= cd -- "${script_dir}/.." && pwd)"

source "$script_dir/common.sh"
load_env_sources
ensure_project_dirs
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
  printf 'No running server marker found. Nothing to stop.\n'
  exit 0
fi

if docker_cmd inspect "$container_id" >/dev/null 2>&1; then
  printf 'Stopping container %s ...\n' "$container_id"
else
  printf 'Container marker is stale: %s\n' "$container_id"
fi

compose_cmd down --remove-orphans

rm -f "$container_id_file" "$pid_file"
printf 'Server stopped.\n'
