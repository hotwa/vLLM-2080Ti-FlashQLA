#!/usr/bin/env bash
set -euo pipefail

# vLLM 2080Ti Definitive - Qwen3.6 27B Safe Profile
# Profile: INT4 + FP16 KV + MTP3 + 256K context + text-only

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

# 环境变量
export PROFILE="qwen27b/safe/int4/fp16kv-256K-mtp3-text-only.env"
export MODE="safe"
export PORT="${PORT:-8000}"
export SERVICE_SCOPE="lan"
export CUDA_VISIBLE_DEVICES="${CUDA_VISIBLE_DEVICES:-0,1}"
export MODEL_DIR="${MODEL_DIR:-/data/models/Qwen3.6-27B-GPTQ-Int4}"

# 打印当前状态
echo "=========================================="
echo " vLLM 2080Ti - Qwen3.6 27B Safe Profile"
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

# 直接启动 vLLM 服务（不通过 launcher.sh，避免烟雾测试后退出）
exec .venv/bin/python -m vllm.entrypoints.openai.api_server \
    --host 0.0.0.0 \
    --port 8000 \
    --model /data/models/Qwen3.6-27B-GPTQ-Int4 \
    --served-model-name qwen27b-int4-fp16kv-256K-mtp3-text-only-cu128 \
    --dtype half \
    --tensor-parallel-size 2 \
    --generation-config vllm \
    --gpu-memory-utilization 0.90 \
    --max-model-len 262144 \
    --enable-chunked-prefill \
    --max-num-seqs 1 \
    --max-num-batched-tokens 2048 \
    --quantization gptq_marlin \
    --language-model-only \
    --skip-mm-profiling \
    --additional-config '{"gdn_prefill_backend":"flashqla_legacy"}' \
    --speculative-config '{"method":"mtp","num_speculative_tokens":3}' \
    --compilation-config '{"cudagraph_capture_sizes":[4],"max_cudagraph_capture_size":4}'
