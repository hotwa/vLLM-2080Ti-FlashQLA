#!/usr/bin/env bash
set -euo pipefail

project_root() {
  local script_dir
  script_dir="$(CDPATH= cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
  CDPATH= cd -- "${script_dir}/.." && pwd
}

load_env_sources() {
  local root
  root="$(project_root)"

  load_env_file_preserve_existing "$root/.env"
  load_env_file_preserve_existing "$root/../CoPaw/.env"
}

load_env_file_preserve_existing() {
  local file="$1"
  local line key value

  [ -f "$file" ] || return 0

  while IFS= read -r line || [ -n "$line" ]; do
    case "$line" in
      ''|\#*)
        continue
        ;;
      export\ *)
        line="${line#export }"
        ;;
    esac

    case "$line" in
      *=*)
        key="${line%%=*}"
        value="${line#*=}"
        key="${key%%[[:space:]]*}"
        if [ -z "${!key+x}" ]; then
          printf -v "$key" '%s' "$value"
          export "$key"
        fi
        ;;
    esac
  done < "$file"
}

setup_logging() {
  local name="${1:-script}"
  local root log_dir log_file
  root="$(project_root)"
  log_dir="${LOG_DIR:-$root/logs}"
  mkdir -p "$log_dir"
  log_file="$log_dir/${name}-$(date +%Y%m%d-%H%M%S).log"
  exec > >(tee -a "$log_file") 2>&1
  printf '[log] %s\n' "$log_file"
}

ensure_venv() {
  local root venv_dir py pip
  root="$(project_root)"
  venv_dir="$root/.venv"
  py="$venv_dir/bin/python"
  pip="$venv_dir/bin/pip"

  if [ ! -x "$py" ]; then
    python3 -m venv "$venv_dir"
  fi

  "$pip" install --upgrade pip setuptools wheel >/dev/null
  "$pip" install --upgrade huggingface_hub requests tqdm >/dev/null
}

runtime_dir() {
  local root
  root="$(project_root)"
  printf '%s\n' "$root/artifacts/runtime"
}

runtime_mode_file() {
  printf '%s\n' "$(runtime_dir)/runtime.mode"
}

runtime_pid_file() {
  printf '%s\n' "$(runtime_dir)/llama-server.pid"
}

runtime_log_file() {
  printf '%s\n' "$(runtime_dir)/llama-server.log"
}

runtime_session_file() {
  printf '%s\n' "$(runtime_dir)/llama-server.tmux-session"
}

ik_llama_source_dir() {
  local root
  root="$(project_root)"
  printf '%s\n' "$root/third_party/ik_llama.cpp"
}

ik_llama_build_dir() {
  local root
  root="$(project_root)"
  printf '%s\n' "${IK_LLAMA_BUILD_DIR:-$root/third_party/ik_llama.cpp/build-qwen36-2080ti}"
}

llama_server_bin() {
  local candidate

  if [ -n "${LLAMA_SERVER_BIN:-}" ] && [ -x "${LLAMA_SERVER_BIN}" ]; then
    printf '%s\n' "$LLAMA_SERVER_BIN"
    return 0
  fi

  for candidate in \
    "$(ik_llama_build_dir)/bin/llama-server" \
    "$(project_root)/third_party/ik_llama.cpp/build/bin/llama-server"
  do
    if [ -x "$candidate" ]; then
      printf '%s\n' "$candidate"
      return 0
    fi
  done

  if command -v llama-server >/dev/null 2>&1; then
    printf '%s\n' "$(command -v llama-server)"
    return 0
  fi

  return 1
}

resolve_hf_token() {
  local root token_file token
  root="$(project_root)"

  if [ -n "${HF_TOKEN:-}" ]; then
    printf '%s\n' "$HF_TOKEN"
    return 0
  fi
  if [ -n "${HUGGINGFACE_TOKEN:-}" ]; then
    printf '%s\n' "$HUGGINGFACE_TOKEN"
    return 0
  fi
  if [ -n "${HUGGING_FACE_HUB_TOKEN:-}" ]; then
    printf '%s\n' "$HUGGING_FACE_HUB_TOKEN"
    return 0
  fi

  for token_file in \
    "$root/.env" \
    "$root/../CoPaw/.env" \
    "$HOME/.huggingface/token" \
    "$HOME/.cache/huggingface/token"
  do
    if [ -f "$token_file" ]; then
      token="$(grep -E '^HF_TOKEN=' "$token_file" 2>/dev/null | head -n1 | cut -d= -f2- || true)"
      if [ -n "$token" ] && [ "$token" != "replace_me" ]; then
        printf '%s\n' "$token"
        return 0
      fi
      token="$(grep -E '^HUGGINGFACE_TOKEN=' "$token_file" 2>/dev/null | head -n1 | cut -d= -f2- || true)"
      if [ -n "$token" ] && [ "$token" != "replace_me" ]; then
        printf '%s\n' "$token"
        return 0
      fi
      token="$(grep -E '^HUGGING_FACE_HUB_TOKEN=' "$token_file" 2>/dev/null | head -n1 | cut -d= -f2- || true)"
      if [ -n "$token" ] && [ "$token" != "replace_me" ]; then
        printf '%s\n' "$token"
        return 0
      fi
    fi
  done

  return 1
}

resolve_hf_token_source() {
  local root token_file
  root="$(project_root)"

  if [ -n "${HF_TOKEN:-}" ]; then
    printf '%s\n' "env:HF_TOKEN"
    return 0
  fi
  if [ -n "${HUGGINGFACE_TOKEN:-}" ]; then
    printf '%s\n' "env:HUGGINGFACE_TOKEN"
    return 0
  fi
  if [ -n "${HUGGING_FACE_HUB_TOKEN:-}" ]; then
    printf '%s\n' "env:HUGGING_FACE_HUB_TOKEN"
    return 0
  fi

  for token_file in \
    "$root/.env" \
    "$root/../CoPaw/.env" \
    "$HOME/.huggingface/token" \
    "$HOME/.cache/huggingface/token"
  do
    if [ -f "$token_file" ]; then
      if grep -q '^HF_TOKEN=' "$token_file"; then
        printf '%s\n' "$token_file:HF_TOKEN"
        return 0
      fi
      if grep -q '^HUGGINGFACE_TOKEN=' "$token_file"; then
        printf '%s\n' "$token_file:HUGGINGFACE_TOKEN"
        return 0
      fi
      if grep -q '^HUGGING_FACE_HUB_TOKEN=' "$token_file"; then
        printf '%s\n' "$token_file:HUGGING_FACE_HUB_TOKEN"
        return 0
      fi
    fi
  done

  if command -v huggingface-cli >/dev/null 2>&1; then
    if huggingface-cli whoami >/dev/null 2>&1; then
      printf '%s\n' "huggingface-cli:authenticated"
      return 0
    fi
  fi

  return 1
}
