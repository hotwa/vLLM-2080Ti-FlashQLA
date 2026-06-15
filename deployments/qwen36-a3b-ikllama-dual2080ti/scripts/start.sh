#!/usr/bin/env bash
set -euo pipefail

script_dir="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)"
project_dir="$(CDPATH= cd -- "${script_dir}/.." && pwd)"

source "$script_dir/common.sh"
load_env_sources
setup_logging "$(basename "$0" .sh)"

runtime_dir="$(runtime_dir)"
runtime_mode_file="$(runtime_mode_file)"
runtime_pid_file="$(runtime_pid_file)"
runtime_log_file="$(runtime_log_file)"
runtime_session_file="$(runtime_session_file)"

mkdir -p "$runtime_dir"

if [ -f "$runtime_session_file" ]; then
  existing_session="$(cat "$runtime_session_file" 2>/dev/null || true)"
  if [ -n "$existing_session" ] && command -v tmux >/dev/null 2>&1 && tmux has-session -t "$existing_session" 2>/dev/null; then
    printf 'Server already running (tmux session=%s).\n' "$existing_session"
    exit 0
  fi
fi

if [ -f "$runtime_pid_file" ]; then
  existing_pid="$(cat "$runtime_pid_file" 2>/dev/null || true)"
  if [ -n "$existing_pid" ] && kill -0 "$existing_pid" 2>/dev/null; then
    printf 'Server already running (pid=%s).\n' "$existing_pid"
    exit 0
  fi
fi

if [ ! -f "$project_dir/${MODEL_DIR:-./models/gguf}/${MODEL_FILE:-Qwen3.6-35B-A3B-Opus-Q5_K_M.gguf}" ]; then
  printf 'Model file is missing; downloading first.\n'
  "$script_dir/download_model.sh"
fi

if [ ! -d "$project_dir/third_party/ik_llama.cpp/.git" ]; then
  printf 'ik_llama.cpp source is missing; fetching it first.\n'
  "$script_dir/fetch_ik_llama.sh"
fi

use_host_runtime=1
if [ "${USE_DOCKER_RUNTIME:-0}" = "1" ]; then
  use_host_runtime=0
fi

if [ "$use_host_runtime" -eq 1 ]; then
  server_bin="${LLAMA_SERVER_BIN:-}"
  if [ -z "$server_bin" ]; then
    server_bin="$(llama_server_bin || true)"
  fi
  if [ -z "$server_bin" ] || [ ! -x "$server_bin" ]; then
    printf 'Local llama-server binary is missing; building it first.\n'
    "$script_dir/build.sh"
    server_bin="$(llama_server_bin)"
  fi

  printf 'Starting host llama-server from %s...\n' "$server_bin"

  model_file="${MODEL_FILE:-Qwen3.6-35B-A3B-Opus-Q5_K_M.gguf}"
  if [[ "$model_file" != /* ]]; then
    model_dir="${MODEL_DIR:-./models/gguf}"
    model_file="$project_dir/${model_dir#./}/$model_file"
  fi
  model_name="${MODEL_NAME:-Qwen3.6-35B-A3B-Opus-Q5_K_M}"
  chat_template_file="${CHAT_TEMPLATE_FILE:-./jinja/qwopus_v3_template.jinja}"
  if [[ "$chat_template_file" != /* ]]; then
    chat_template_file="$project_dir/${chat_template_file#./}"
  fi
  ctx_size="${MAX_MODEL_LEN:-131072}"
  n_parallel="${N_PARALLEL:-1}"
  n_gpu_layers="${N_GPU_LAYERS:-999}"
  split_mode="${SPLIT_MODE:-graph}"
  tensor_split="${TENSOR_SPLIT:-50,50}"
  ubatch="${UBATCH:-512}"
  batch="${BATCH:-2048}"
  threads="${THREADS:-4}"
  cache_type_k="${CACHE_TYPE_K:-q8_0}"
  cache_type_v="${CACHE_TYPE_V:-q8_0}"
  flash_attn="${FLASH_ATTN:-1}"
  mla_use="${MLA_USE:-3}"
  attention_max_batch="${ATTENTION_MAX_BATCH:-256}"
  reasoning_tokens="${REASONING_TOKENS:-none}"
  jinja="${JINJA:-1}"
  no_context_shift="${NO_CONTEXT_SHIFT:-1}"
  no_mmap="${NO_MMAP:-1}"
  reasoning_format="${REASONING_FORMAT:-none}"
  reasoning_budget="${REASONING_BUDGET:-0}"
  chat_template_enable_thinking="${CHAT_TEMPLATE_ENABLE_THINKING:-0}"
  sampling_temp="${SAMPLING_TEMP:-0.7}"
  sampling_top_p="${SAMPLING_TOP_P:-0.8}"
  sampling_top_k="${SAMPLING_TOP_K:-20}"
  sampling_min_p="${SAMPLING_MIN_P:-0.0}"
  sampling_presence_penalty="${SAMPLING_PRESENCE_PENALTY:-1.5}"
  if [ "$chat_template_enable_thinking" = "1" ] || [ "$chat_template_enable_thinking" = "true" ]; then
    chat_template_kwargs='{"enable_thinking": true}'
  else
    chat_template_kwargs='{"enable_thinking": false}'
  fi

  if [ ! -f "$model_file" ]; then
    echo "Missing model file: $model_file" >&2
    exit 1
  fi

  if [ "$jinja" = "1" ] && [ ! -f "$chat_template_file" ]; then
    echo "Missing chat template: $chat_template_file" >&2
    exit 1
  fi

  cmd=(
    "$server_bin"
    -m "$model_file"
    -a "$model_name"
    --host 0.0.0.0
    --port "${HOST_PORT:-8000}"
    -c "$ctx_size"
    -np "$n_parallel"
    -ngl "$n_gpu_layers"
    -sm "$split_mode"
    -ts "$tensor_split"
    -ub "$ubatch"
    -b "$batch"
    --threads "$threads"
    --cache-type-k "$cache_type_k"
    --cache-type-v "$cache_type_v"
    --reasoning-format "$reasoning_format"
    --reasoning-tokens "$reasoning_tokens"
    --reasoning-budget "$reasoning_budget"
    --temp "$sampling_temp"
    --top-p "$sampling_top_p"
    --top-k "$sampling_top_k"
    --min-p "$sampling_min_p"
    --presence-penalty "$sampling_presence_penalty"
    -ger
    -mla "$mla_use"
    -amb "$attention_max_batch"
  )

  if [ "$flash_attn" = "1" ]; then
    cmd+=(--flash-attn on)
  fi
  if [ "$jinja" = "1" ]; then
    cmd+=(--jinja --chat-template-file "$chat_template_file")
    cmd+=(--chat-template-kwargs "$chat_template_kwargs")
  else
    cmd+=(--jinja)
    printf 'Using chat template from GGUF metadata (JINJA=0).\n'
  fi
  if [ "$no_context_shift" = "1" ]; then
    cmd+=(--no-context-shift)
  fi
  if [ "$no_mmap" = "1" ]; then
    cmd+=(--no-mmap)
  fi

  if command -v tmux >/dev/null 2>&1; then
    session_name="${LLAMA_SERVER_SESSION:-qwen36-a3b-ikllama}"
    launch_script="$runtime_dir/llama-server-launch.sh"
    mkdir -p "$runtime_dir"

    {
      printf '#!/usr/bin/env bash\n'
      printf 'set -euo pipefail\n'
      printf 'cd %q\n' "$project_dir"
      printf 'exec'
      for arg in "${cmd[@]}"; do
        printf ' %q' "$arg"
      done
      printf '\n'
    } > "$launch_script"
    chmod +x "$launch_script"

    : > "$runtime_log_file"
    tmux new-session -d -s "$session_name" "$launch_script"
    sleep 1
    pane_pid="$(tmux display-message -p -t "$session_name" "#{pane_pid}" 2>/dev/null || true)"
    if [ -n "$pane_pid" ]; then
      printf '%s\n' "$pane_pid" > "$runtime_pid_file"
    fi
    printf '%s\n' "$session_name" > "$runtime_session_file"
    printf '%s\n' "host-tmux" > "$runtime_mode_file"
    printf 'Host server start requested (tmux session=%s, log=%s).\n' "$session_name" "$runtime_log_file"
    exit 0
  fi

  : > "$runtime_log_file"
  nohup "${cmd[@]}" >"$runtime_log_file" 2>&1 &
  server_pid=$!
  printf '%s\n' "$server_pid" > "$runtime_pid_file"
  printf '%s\n' "host-nohup" > "$runtime_mode_file"
  printf 'Host server start requested (pid=%s, log=%s).\n' "$server_pid" "$runtime_log_file"
  exit 0
fi

printf 'Starting server container...\n'
printf '%s\n' "docker" > "$runtime_mode_file"
docker compose --project-directory "$project_dir" -f "$project_dir/docker-compose.yml" up -d --build server
printf 'Server start requested.\n'
