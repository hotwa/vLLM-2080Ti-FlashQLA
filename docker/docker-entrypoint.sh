#!/usr/bin/env bash
set -euo pipefail

# ============================================================
# vLLM 2080Ti FlashQLA - Docker Entrypoint
# Replicates run_qwen27b_fast.sh environment
# ============================================================

# SM75 Runtime Environment
export CUDA_HOME="${CUDA_HOME:-/usr/local/cuda}"
export CUDA_PATH="$CUDA_HOME"
export TORCH_CUDA_ARCH_LIST="${TORCH_CUDA_ARCH_LIST:-7.5}"
export CUDA_VISIBLE_DEVICES="${CUDA_VISIBLE_DEVICES:-0,1}"
export CUDA_DEVICE_ORDER="${CUDA_DEVICE_ORDER:-PCI_BUS_ID}"
export FLASHINFER_ENABLE_AOT="${FLASHINFER_ENABLE_AOT:-1}"
export TORCHINDUCTOR_CACHE_DIR="${TORCHINDUCTOR_CACHE_DIR:-/tmp/torchinductor-cache}"
export TRITON_CACHE_DIR="${TRITON_CACHE_DIR:-/tmp/triton-cache}"
export PYTHONUNBUFFERED=1

# Fast Mode Environment
export VLLM_SM75_SPEC_SYNC_MODE="${VLLM_SM75_SPEC_SYNC_MODE:-nosync}"
export VLLM_ALLOW_MAMBA_SPEC_FULL_CUDAGRAPH="${VLLM_ALLOW_MAMBA_SPEC_FULL_CUDAGRAPH:-1}"
export DISABLE_LOG_STATS="${DISABLE_LOG_STATS:-1}"

# MTP BF16 Draft (for Qwen3.5/3.6 MTP)
export VLLM_QWOPUS_MTP_BF16_DRAFT="${VLLM_QWOPUS_MTP_BF16_DRAFT:-1}"

# Model configuration (can be overridden via environment)
MODEL_DIR="${MODEL_DIR:-/models}"
PORT="${PORT:-8000}"

echo "=========================================="
echo " vLLM 2080Ti FlashQLA (Docker)"
echo "=========================================="
echo ""
echo "GPU Status:"
nvidia-smi --query-gpu=index,name,memory.used,memory.total,temperature.gpu --format=csv,noheader
echo ""
echo "Model Dir: $MODEL_DIR"
echo "Port: $PORT"
echo "CUDA_VISIBLE_DEVICES: $CUDA_VISIBLE_DEVICES"
echo "=========================================="
echo ""

# Check model directory
if [ ! -d "$MODEL_DIR" ]; then
    echo "ERROR: Model directory not found: $MODEL_DIR"
    echo "Mount your model directory to /models (or set MODEL_DIR)"
    exit 1
fi

# Execute vLLM with all args passed through, or use defaults
if [ $# -gt 0 ]; then
    exec python -m vllm.entrypoints.openai.api_server "$@"
else
    exec python -m vllm.entrypoints.openai.api_server \
        --host 0.0.0.0 \
        --port "$PORT" \
        --model "$MODEL_DIR" \
        --served-model-name qwen27b-int4-mtp3 \
        --dtype half \
        --tensor-parallel-size 2 \
        --generation-config vllm \
        --gpu-memory-utilization 0.90 \
        --max-model-len 256000 \
        --enable-chunked-prefill \
        --max-num-seqs 1 \
        --max-num-batched-tokens 2048 \
        --quantization gptq_marlin \
        --disable-custom-all-reduce \
        --language-model-only \
        --skip-mm-profiling \
        --chat-template /opt/vllm/docker/chat_template_no_thinking.jinja \
        --enable-auto-tool-choice \
        --tool-call-parser hermes \
        --speculative-config '{"method":"mtp","num_speculative_tokens":3}' \
        --compilation-config '{"cudagraph_capture_sizes":[4],"max_cudagraph_capture_size":4}'
fi
