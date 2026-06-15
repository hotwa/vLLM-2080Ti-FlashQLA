FROM vllm/vllm-openai:v0.21.0-ubuntu2404

ARG VLLM_DFLASH_REF=refs/pull/40898/head

ENV DEBIAN_FRONTEND=noninteractive

RUN apt-get update \
    && apt-get install -y --no-install-recommends \
        ca-certificates \
        git \
    && rm -rf /var/lib/apt/lists/*

# Docker build has no GPU device to auto-detect, so pin the CUDA 13 backend.
RUN VLLM_USE_PRECOMPILED=1 VLLM_PRECOMPILED_WHEEL_VARIANT=cu130 \
    uv pip install --system -U --torch-backend=cu130 \
    "vllm @ git+https://github.com/vllm-project/vllm.git@${VLLM_DFLASH_REF}"

RUN uv pip install --system xxhash

RUN python3 - <<'PYEOF'
from pathlib import Path

import vllm
import xxhash  # noqa: F401

import vllm.model_executor.models.qwen3_dflash  # noqa: F401
import vllm.v1.spec_decode.dflash  # noqa: F401

flash_attn_dir = Path(vllm.__file__).resolve().parent / "vllm_flash_attn"
assert flash_attn_dir.is_dir(), "vLLM FlashAttention package is missing"
assert list(flash_attn_dir.rglob("*.so")), "vLLM FlashAttention shared objects are missing"

print("[SANITY] vLLM DFlash modules import successfully")
print(f"[SANITY] Found vLLM FlashAttention objects in {flash_attn_dir}")
PYEOF
