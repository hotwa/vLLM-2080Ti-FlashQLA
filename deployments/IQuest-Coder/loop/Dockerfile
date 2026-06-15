FROM nvidia/cuda:12.9.1-devel-ubuntu22.04

# ========== 代理配置（放最前面） ==========
ARG HTTP_PROXY
ARG HTTPS_PROXY
ARG NO_PROXY
ARG http_proxy
ARG https_proxy
ARG no_proxy

ENV HTTP_PROXY=${HTTP_PROXY} \
    HTTPS_PROXY=${HTTPS_PROXY} \
    NO_PROXY=${NO_PROXY} \
    http_proxy=${http_proxy:-$HTTP_PROXY} \
    https_proxy=${https_proxy:-$HTTPS_PROXY} \
    no_proxy=${no_proxy:-$NO_PROXY}

ENV DEBIAN_FRONTEND=noninteractive \
    PIP_DISABLE_PIP_VERSION_CHECK=1 \
    PIP_NO_CACHE_DIR=1 \
    MAX_JOBS=12 \
    NVCC_THREADS=1 \
    CMAKE_BUILD_PARALLEL_LEVEL=12 \
    TORCH_CUDA_ARCH_LIST=12.0


# 只用 apt 装基础编译工具/运行环境（不装 cmake）
RUN apt-get update && apt-get install -y --no-install-recommends \
    git \
    build-essential \
    ninja-build \
    python3 \
    python3-pip \
    python3-dev \
    ca-certificates \
    curl \
    jq \
    && rm -rf /var/lib/apt/lists/*

# ========== 为 git 显式配置代理 ==========
RUN if [ -n "$HTTP_PROXY" ]; then \
      git config --global http.proxy "$HTTP_PROXY" && \
      git config --global https.proxy "$HTTPS_PROXY"; \
    fi

# 用 pip 装新版 cmake（>=3.26）+ 基础构建链（setuptools/wheel/numpy 等）
RUN python3 -m pip install -U pip setuptools wheel \
 && python3 -m pip install "cmake>=3.26" ninja numpy

# 安装匹配 CUDA 12.9 的 torch（按你的方案走 cu129）
RUN python3 -m pip install torch --index-url https://download.pytorch.org/whl/cu129

# 可选：把 pip 的 cmake 放到前面，确保构建时用的是 pip 的 cmake
ENV PATH="/usr/local/bin:${PATH}"

# 安装 vLLM（你之前的 PR ref）
RUN python3 -m pip install -U pip setuptools wheel && \
    python3 -m pip install -U setuptools_scm && \
    python3 -m pip uninstall -y vllm || true
ARG VLLM_COMMIT=6fb9ceca3e3b882d4fe64622e2965379332d967e
RUN python3 -m pip install -v --no-cache-dir --no-build-isolation \
  "git+https://github.com/vllm-project/vllm.git@${VLLM_COMMIT}"

RUN python3 - <<'PY'
import vllm.model_executor.models.registry as r
assert "IQuestLoopCoderForCausalLM" in r._TEXT_GENERATION_MODELS
print("OK: IQuestLoopCoderForCausalLM registered")
PY

# ========== 清除代理配置（运行时不需要） ==========
RUN git config --global --unset http.proxy || true && \
    git config --global --unset https.proxy || true

ENV HTTP_PROXY="" \
    HTTPS_PROXY="" \
    NO_PROXY="" \
    http_proxy="" \
    https_proxy="" \
    no_proxy=""

