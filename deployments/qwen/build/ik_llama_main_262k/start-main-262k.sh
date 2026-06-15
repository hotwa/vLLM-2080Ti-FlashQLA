#!/usr/bin/env bash
set -euo pipefail

mkdir -p /models

MODEL_PATH="${MODEL_PATH:-/models/Qwen3.6-27B-Q4_K_M.gguf}"
MODEL_REPO="${MODEL_REPO:-unsloth/Qwen3.6-27B-GGUF}"
MODEL_FILE="${MODEL_FILE:-Qwen3.6-27B-Q4_K_M.gguf}"
MODEL_ALIAS="${MODEL_ALIAS:-Qwen3.6-27B}"
HOST="${HOST:-0.0.0.0}"
PORT="${PORT:-8080}"
MTP="${MTP:-off}"
SPEC_DRAFT_N_MAX="${SPEC_DRAFT_N_MAX:-6}"
CTX_SIZE="${CTX_SIZE:-262144}"
N_PREDICT="${N_PREDICT:-1024}"
NP="${NP:-1}"
BATCH_SIZE="${BATCH_SIZE:-256}"
UBATCH_SIZE="${UBATCH_SIZE:-128}"
N_GPU_LAYERS="${N_GPU_LAYERS:-999}"
SPLIT_MODE="${SPLIT_MODE:-graph}"
TENSOR_SPLIT="${TENSOR_SPLIT:-40,60}"
FLASH_ATTN="${FLASH_ATTN:-on}"
REASONING="${REASONING:-off}"
EXTRA_ARGS="${EXTRA_ARGS:---cache-ram 0}"
SERVER_BIN="/opt/ik_llama.cpp/build/bin/llama-server"

if [ ! -f "$MODEL_PATH" ]; then
    echo "[INFO] Model not found: $MODEL_PATH"
    echo "[INFO] Downloading ${MODEL_REPO}/${MODEL_FILE} to /models"
    huggingface-cli download "$MODEL_REPO" "$MODEL_FILE" --local-dir /models
fi

echo "[INFO] nvidia-smi:"
nvidia-smi || true

echo "[INFO] nvidia-smi topo -m:"
nvidia-smi topo -m || true

if [ ! -x "$SERVER_BIN" ]; then
    echo "[ERROR] llama-server not found or not executable: $SERVER_BIN" >&2
    exit 1
fi

SERVER_HELP="$("$SERVER_BIN" --help 2>&1 || true)"

has_flag() {
    local flag="$1"
    grep -Eq -- "(^|[[:space:],])${flag}([[:space:],=]|$)" <<<"$SERVER_HELP"
}

resolve_flag() {
    local env_name="$1"
    shift
    local flag
    for flag in "$@"; do
        if has_flag "$flag"; then
            printf '%s' "$flag"
            return 0
        fi
    done
    echo "[ERROR] llama-server does not support required ${env_name} flag. Tried: $*" >&2
    exit 1
}

PREDICT_FLAG="$(resolve_flag N_PREDICT -n --predict --n-predict)"
FLASH_ATTN_FLAG="$(resolve_flag FLASH_ATTN -fa --flash-attn)"
SPLIT_MODE_FLAG="$(resolve_flag SPLIT_MODE -sm --split-mode)"
TENSOR_SPLIT_FLAG="$(resolve_flag TENSOR_SPLIT -ts --tensor-split)"

reasoning_args=()
if has_flag --reasoning; then
    reasoning_args+=(--reasoning "$REASONING")
fi
if has_flag --reasoning-format; then
    reasoning_args+=(--reasoning-format none)
fi
if has_flag --reasoning-tokens; then
    reasoning_args+=(--reasoning-tokens none)
fi

mtp_args=()
if [[ "${MTP,,}" == "on" ]]; then
    if has_flag --spec-stage; then
        mtp_args+=(--spec-stage "mtp:n_max=${SPEC_DRAFT_N_MAX}")
        echo "[INFO] MTP enabled: --spec-stage mtp:n_max=${SPEC_DRAFT_N_MAX}"
    elif has_flag -mtp; then
        mtp_args+=(-mtp --draft-n "$SPEC_DRAFT_N_MAX")
        echo "[INFO] MTP enabled: -mtp --draft-n $SPEC_DRAFT_N_MAX"
    else
        echo "[WARN] llama-server does not support MTP, disabled"
    fi
else
    if has_flag -no-mtp; then
        mtp_args+=(-no-mtp)
    elif has_flag --no-multi-token-prediction; then
        mtp_args+=(--no-multi-token-prediction)
    fi
fi

cmd=(
    "$SERVER_BIN"
    -m "$MODEL_PATH"
    -a "$MODEL_ALIAS"
    -ngl "$N_GPU_LAYERS"
    "$SPLIT_MODE_FLAG" "$SPLIT_MODE"
    "$TENSOR_SPLIT_FLAG" "$TENSOR_SPLIT"
    -np "$NP"
    -c "$CTX_SIZE"
    "$PREDICT_FLAG" "$N_PREDICT"
    "$FLASH_ATTN_FLAG" "$FLASH_ATTN"
    -b "$BATCH_SIZE"
    -ub "$UBATCH_SIZE"
    --host "$HOST"
    --port "$PORT"
    --jinja
    "${reasoning_args[@]}"
    "${mtp_args[@]}"
    --chat-template-kwargs '{"enable_thinking": false}'
)

if [ -n "$EXTRA_ARGS" ]; then
    # EXTRA_ARGS is intentionally shell-split so advanced llama-server flags can be passed from compose.
    # shellcheck disable=SC2206
    extra_args=( $EXTRA_ARGS )
    cmd+=("${extra_args[@]}")
fi

echo "[INFO] Starting llama-server:"
printf ' %q' "${cmd[@]}"
echo

exec "${cmd[@]}"
