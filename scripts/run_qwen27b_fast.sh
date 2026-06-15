#!/usr/bin/env bash
set -euo pipefail

# vLLM 2080Ti Definitive - Qwen3.6 27B Fast Profile
# Profile: INT4 + INT8 KV + MTP3 + 256K context + text-only
# WARNING: 这是性能/容量路线，用于测试，不作为默认生产服务

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

# === SM75 Runtime Environment (from launcher.sh set_sm75_runtime_env) ===
export CUDA_HOME="${CUDA_HOME:-/usr/local/cuda-12.8}"
export CUDA_PATH="$CUDA_HOME"
export CUDACXX="$CUDA_HOME/bin/nvcc"
export TORCH_CUDA_ARCH_LIST="${TORCH_CUDA_ARCH_LIST:-7.5}"
export CUDA_VISIBLE_DEVICES="${CUDA_VISIBLE_DEVICES:-0,1}"
export CUDA_DEVICE_ORDER="${CUDA_DEVICE_ORDER:-PCI_BUS_ID}"
export FLASHINFER_ENABLE_AOT="${FLASHINFER_ENABLE_AOT:-1}"
export PYTHONPATH="$SCRIPT_DIR:$SCRIPT_DIR/FlashQLA-SM70-SM75${PYTHONPATH:+:$PYTHONPATH}"
export PATH="$SCRIPT_DIR/.venv/bin:${CUDA_HOME}/bin:$PATH"
export TORCHINDUCTOR_CACHE_DIR="$SCRIPT_DIR/torchinductor-cache"
export TRITON_CACHE_DIR="$SCRIPT_DIR/triton-cache"
export PYTHONUNBUFFERED=1

# === Fast Mode Environment (from launcher.sh apply_mode) ===
export VLLM_SM75_SPEC_SYNC_MODE="${VLLM_SM75_SPEC_SYNC_MODE_OVERRIDE:-nosync}"
export VLLM_ALLOW_MAMBA_SPEC_FULL_CUDAGRAPH=1
export DISABLE_LOG_STATS="${DISABLE_LOG_STATS:-1}"

# === INT8 KV Cache Environment (from launcher.sh set_sm75_runtime_env) ===
export VLLM_INT8KV_FA_PREFILL=1
export VLLM_INT8KV_FA_CONTINUATION_DEQUANT=1
export VLLM_INT8KV_FA_CASCADE_DEQUANT=1
export VLLM_INT8KV_FA_CASCADE_TILE_TOKENS=65536

# === Profile Variables ===
export PROFILE="qwen27b/fast/int4/int8kv-256K-mtp3-text-only.env"
export MODE="fast"
export PORT="${PORT:-8000}"
export SERVICE_SCOPE="lan"
export MODEL_DIR="${MODEL_DIR:-/data/models/Qwen3.6-27B-GPTQ-Int4}"

# 打印当前状态
echo "=========================================="
echo " vLLM 2080Ti - Qwen3.6 27B Fast Profile"
echo " WARNING: 性能/容量路线，用于测试"
echo "=========================================="
echo ""
echo "GPU Status:"
nvidia-smi --query-gpu=index,name,memory.used,memory.total,temperature.gpu --format=csv,noheader
echo ""
echo "Profile: $PROFILE"
echo "Mode: $MODE"
echo "Port: $PORT"
echo "CUDA_VISIBLE_DEVICES: $CUDA_VISIBLE_DEVICES"
echo "Model Dir: $MODEL_DIR"
echo "KV Cache: int8_per_token_head"
echo "VLLM_SM75_SPEC_SYNC_MODE: $VLLM_SM75_SPEC_SYNC_MODE"
echo "VLLM_ALLOW_MAMBA_SPEC_FULL_CUDAGRAPH: $VLLM_ALLOW_MAMBA_SPEC_FULL_CUDAGRAPH"
echo "=========================================="
echo ""

# 检查模型目录
if [ ! -d "$MODEL_DIR" ]; then
    echo "ERROR: Model directory not found: $MODEL_DIR"
    exit 1
fi

# 检查是否有 safetensors 文件
if ! ls "$MODEL_DIR"/*.safetensors 1>/dev/null 2>&1; then
    echo "ERROR: No safetensors files found in $MODEL_DIR"
    exit 1
fi

# 直接启动 vLLM 服务（fast 模式，INT8 KV）
exec .venv/bin/python -m vllm.entrypoints.openai.api_server \
    --host 0.0.0.0 \
    --port 8000 \
    --model /data/models/Qwen3.6-27B-GPTQ-Int4 \
    --served-model-name qwen27b-int4-int8kv-256K-mtp3-text-only-cu128 \
    --dtype half \
    --tensor-parallel-size 2 \
    --generation-config vllm \
    --gpu-memory-utilization 0.90 \
    --max-model-len 262144 \
    --enable-chunked-prefill \
    --max-num-seqs 1 \
    --max-num-batched-tokens 2048 \
    --quantization gptq_marlin \
    --kv-cache-dtype int8_per_token_head \
    --disable-custom-all-reduce \
    --language-model-only \
    --skip-mm-profiling \
    --additional-config '{"gdn_prefill_backend":"flashqla_legacy","disable_custom_all_reduce":true}' \
    --speculative-config '{"method":"mtp","num_speculative_tokens":3}' \
    --compilation-config '{"cudagraph_capture_sizes":[4],"max_cudagraph_capture_size":4}'
