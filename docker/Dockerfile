# ============================================================
# vLLM 2080Ti FlashQLA - Multi-stage Docker Build
# ============================================================
# Builder:  nvidia/cuda:12.8.1-devel-ubuntu24.04  (includes nvcc)
# Runtime:  nvidia/cuda:12.8.1-runtime-ubuntu24.04 (smaller)
# ============================================================

# --------------- Builder stage ---------------
FROM nvidia/cuda:12.8.1-devel-ubuntu24.04 AS builder

ENV DEBIAN_FRONTEND=noninteractive
ENV CUDA_HOME=/usr/local/cuda
ENV CUDA_PATH=/usr/local/cuda
ENV CUDACXX=/usr/local/cuda/bin/nvcc
ENV PATH="/usr/local/cuda/bin:${PATH}"

# Install system dependencies (Python 3.11 via deadsnakes PPA on Ubuntu 24.04)
RUN apt-get update && apt-get install -y --no-install-recommends \
        software-properties-common \
    && add-apt-repository ppa:deadsnakes/ppa -y \
    && apt-get update && apt-get install -y --no-install-recommends \
        python3.11 python3.11-venv python3.11-dev \
        git curl wget \
        build-essential cmake ninja-build \
    && rm -rf /var/lib/apt/lists/*

# Install uv (fast Python package manager)
RUN curl -LsSf https://astral.sh/uv/install.sh | sh
ENV PATH="/root/.local/bin:${PATH}"

WORKDIR /build

# Copy source code
COPY . .

# Build environment variables
ENV TORCH_CUDA_ARCH_LIST=7.5
ENV FLASHINFER_ENABLE_AOT=1
# Use all available CPU cores for parallel compilation (max 16 to avoid OOM)
# GitHub Actions has 2-4 cores, local machines may have more
ARG MAX_JOBS=16
ENV MAX_JOBS=${MAX_JOBS}
ENV CMAKE_BUILD_TYPE=Release
ENV TORCH_EXTENSIONS_DIR=/opt/torch_extensions_cache
ENV VLLM_TARGET_DEVICE=cuda

# Create venv and install deps
RUN uv venv --python 3.11 /build/.venv
ENV PATH="/build/.venv/bin:${PATH}"

RUN uv pip install -U pip setuptools wheel
RUN uv pip install -r requirements/build/cuda.txt --torch-backend=cu128
RUN uv pip install -r requirements/cuda.txt --torch-backend=cu128

# Build vLLM (editable install so __file__ resolves correctly)
# SETUPTOOLS_SCM_PRETEND_VERSION needed because .git is excluded by .dockerignore
ENV SETUPTOOLS_SCM_PRETEND_VERSION=0.1.6
RUN uv pip install --no-build-isolation -e .

# Fix editable install paths: /build -> /opt/vllm (for runtime stage)
RUN SITE=$(/build/.venv/bin/python -c "import site; print(site.getsitepackages()[0])") && \
    for f in "$SITE"/__editable__*finder*.py; do \
        [ -f "$f" ] && sed -i 's|/build|/opt/vllm|g' "$f"; \
    done

# --------------- Runtime stage ---------------
# Must use devel image for FlashQLA CUDA kernel compilation (requires nvcc)
FROM nvidia/cuda:12.8.1-devel-ubuntu24.04 AS runtime

ENV DEBIAN_FRONTEND=noninteractive
ENV CUDA_HOME=/usr/local/cuda
ENV CUDA_PATH=/usr/local/cuda
ENV CUDACXX=/usr/local/cuda/bin/nvcc
ENV PATH="/usr/local/cuda/bin:${PATH}"

# Install runtime dependencies (Python 3.11 via deadsnakes PPA)
RUN apt-get update && apt-get install -y --no-install-recommends \
        software-properties-common \
    && add-apt-repository ppa:deadsnakes/ppa -y \
    && apt-get update && apt-get install -y --no-install-recommends \
        python3.11 python3.11-venv libpython3.11 \
        curl build-essential ninja-build \
    && rm -rf /var/lib/apt/lists/*

# Copy Python environment (with fixed editable paths)
COPY --from=builder /build/.venv /opt/venv
ENV PATH="/opt/venv/bin:${PATH}"

# Copy only necessary source files (not build cache)
COPY --from=builder /build/vllm /opt/vllm/vllm
COPY --from=builder /build/csrc /opt/vllm/csrc
COPY --from=builder /build/FlashQLA-SM70-SM75 /opt/vllm/FlashQLA-SM70-SM75
COPY --from=builder /build/setup.py /opt/vllm/
COPY --from=builder /build/pyproject.toml /opt/vllm/
COPY --from=builder /build/CMakeLists.txt /opt/vllm/
COPY --from=builder /build/docker/docker-entrypoint.sh /opt/vllm/docker/docker-entrypoint.sh

WORKDIR /opt/vllm

# Runtime environment
ENV TORCH_CUDA_ARCH_LIST=7.5
ENV FLASHINFER_ENABLE_AOT=1
ENV TORCH_EXTENSIONS_DIR=/tmp/torch_extensions_cache
ENV PYTHONPATH="/opt/vllm:/opt/vllm/FlashQLA-SM70-SM75"
ENV PYTHONUNBUFFERED=1

EXPOSE 8000

# Health check
HEALTHCHECK --interval=30s --timeout=10s --start-period=300s --retries=3 \
    CMD curl -f http://localhost:8000/health || exit 1

ENTRYPOINT ["/opt/vllm/docker/docker-entrypoint.sh"]
