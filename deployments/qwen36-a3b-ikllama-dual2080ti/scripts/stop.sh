#!/usr/bin/env bash
set -euo pipefail

script_dir="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)"
project_dir="$(CDPATH= cd -- "${script_dir}/.." && pwd)"

source "$script_dir/common.sh"
load_env_sources
setup_logging "$(basename "$0" .sh)"

runtime_mode_file="$(runtime_mode_file)"
runtime_pid_file="$(runtime_pid_file)"
runtime_session_file="$(runtime_session_file)"
runtime_dir="$(runtime_dir)"

runtime_mode="host"
if [ -f "$runtime_mode_file" ]; then
  runtime_mode="$(cat "$runtime_mode_file" 2>/dev/null || printf '%s' 'host')"
fi

if [ "$runtime_mode" = "host" ] || [ -f "$runtime_pid_file" ] || [ -f "$runtime_session_file" ]; then
  if [ -f "$runtime_session_file" ]; then
    session_name="$(cat "$runtime_session_file" 2>/dev/null || true)"
    if [ -n "$session_name" ] && command -v tmux >/dev/null 2>&1 && tmux has-session -t "$session_name" 2>/dev/null; then
      printf 'Stopping host tmux session=%s...\n' "$session_name"
      tmux kill-session -t "$session_name"
      rm -f "$runtime_session_file" "$runtime_pid_file" "$runtime_mode_file" "$runtime_dir/llama-server-launch.sh"
      printf 'Host server stop complete.\n'
      exit 0
    fi
  fi

  if [ -f "$runtime_pid_file" ]; then
    server_pid="$(cat "$runtime_pid_file" 2>/dev/null || true)"
    if [ -n "$server_pid" ] && kill -0 "$server_pid" 2>/dev/null; then
      printf 'Stopping host server pid=%s...\n' "$server_pid"
      kill "$server_pid"
      for _ in $(seq 1 30); do
        if kill -0 "$server_pid" 2>/dev/null; then
          sleep 1
        else
          break
        fi
      done
    fi
    rm -f "$runtime_pid_file"
  fi
  rm -f "$runtime_mode_file" "$runtime_session_file" "$runtime_dir/llama-server-launch.sh"
  printf 'Host server stop complete.\n'
  exit 0
fi

printf 'Stopping server container...\n'
docker compose --project-directory "$project_dir" -f "$project_dir/docker-compose.yml" down --remove-orphans
printf 'Server stop requested.\n'
