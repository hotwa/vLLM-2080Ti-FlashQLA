#!/usr/bin/env bash
set -euo pipefail

project_root() {
  local script_dir
  script_dir="$(CDPATH= cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
  CDPATH= cd -- "${script_dir}/.." && pwd
}

die() {
  printf 'Error: %s\n' "$*" >&2
  exit 1
}

require_command() {
  local name="$1"
  command -v "$name" >/dev/null 2>&1 || die "Missing required command: $name"
}

load_env_file() {
  local file="$1"
  [ -f "$file" ] || return 0
  set -a
  # shellcheck disable=SC1090
  . "$file"
  set +a
}

load_env_sources() {
  local root
  root="$(project_root)"
  load_env_file "$root/.env"
}

ensure_project_dirs() {
  local root
  root="$(project_root)"
  mkdir -p "$root/models" "$root/repos" "$root/logs" "$root/run"
}

docker_cmd() {
  if command -v docker >/dev/null 2>&1; then
    if docker info >/dev/null 2>&1; then
      docker "$@"
      return 0
    fi
    if command -v sudo >/dev/null 2>&1; then
      sudo docker "$@"
      return 0
    fi
  fi
  die "Docker is not available. Install Docker Engine and ensure you can run docker commands."
}

compose_cmd() {
  if command -v docker >/dev/null 2>&1; then
    if docker info >/dev/null 2>&1 && docker compose version >/dev/null 2>&1; then
      docker compose "$@"
      return 0
    fi
  fi
  if command -v docker-compose >/dev/null 2>&1; then
    docker-compose "$@"
    return 0
  fi
  if command -v docker >/dev/null 2>&1 && command -v sudo >/dev/null 2>&1; then
    sudo docker compose "$@"
    return 0
  fi
  die "Docker Compose is not available. Install docker compose v2 or docker-compose."
}

require_nvidia_gpu() {
  require_command nvidia-smi
  if ! nvidia-smi -L >/dev/null 2>&1; then
    die "NVIDIA GPU / driver not visible. This deployment does not fall back to CPU."
  fi
}

detect_cuda_arch() {
  if [ -n "${CMAKE_CUDA_ARCHITECTURES:-}" ]; then
    printf '%s\n' "$CMAKE_CUDA_ARCHITECTURES"
    return 0
  fi

  require_command nvidia-smi
  local arch
  arch="$(nvidia-smi --query-gpu=compute_cap --format=csv,noheader 2>/dev/null | head -n1 | tr -d '.[:space:]')"
  [ -n "$arch" ] || die "Unable to detect CUDA architecture from nvidia-smi."
  printf '%s\n' "$arch"
}

resolve_host_path() {
  local path="$1"
  local root
  root="$(project_root)"
  case "$path" in
    /*) printf '%s\n' "$path" ;;
    ./*) printf '%s\n' "$root/${path#./}" ;;
    *) printf '%s\n' "$root/$path" ;;
  esac
}

model_alias_from_path() {
  local path="$1"
  local name
  name="$(basename "$path")"
  printf '%s\n' "${name%.gguf}"
}

runtime_dir() {
  printf '%s\n' "$(project_root)/run"
}

runtime_log_file() {
  printf '%s\n' "$(project_root)/logs/llama-server.log"
}

runtime_pid_file() {
  printf '%s\n' "$(runtime_dir)/llama-server.pid"
}

runtime_container_file() {
  printf '%s\n' "$(runtime_dir)/llama-server.container_id"
}

wait_for_http() {
  local url="$1"
  local timeout="${2:-60}"
  local interval="${3:-2}"
  local api_key="${4:-}"
  local elapsed=0
  local -a curl_args=(-fsS)

  if [ -n "$api_key" ]; then
    curl_args+=(-H "Authorization: Bearer ${api_key}")
  fi

  while [ "$elapsed" -lt "$timeout" ]; do
    if curl "${curl_args[@]}" "$url" >/dev/null 2>&1; then
      return 0
    fi
    sleep "$interval"
    elapsed=$((elapsed + interval))
  done

  return 1
}
