# Combined build + tooling image.
#
# The runtime server and the conversion / merge tools intentionally share the same
# pinned environment so the GGUF conversion path and the serving path do not drift.
#
# The transformers pin is only used by the merge/export tooling. The server binary
# itself does not depend on transformers at runtime.

ARG CUDA_VERSION=12.8.1
FROM nvidia/cuda:${CUDA_VERSION}-devel-ubuntu24.04 AS base

ARG DEBIAN_FRONTEND=noninteractive
ARG IK_LLAMA_REF=64234e3c4ea9c3cd2dd1a4f84c7da38e9607c747
ARG CMAKE_CUDA_ARCHITECTURES=75
ARG TRANSFORMERS_VERSION=5.3.0

ENV PIP_NO_CACHE_DIR=1 \
    PYTHONUNBUFFERED=1 \
    HF_HOME=/root/.cache \
    HF_HUB_CACHE=/root/.cache/huggingface \
    TRANSFORMERS_CACHE=/root/.cache/huggingface \
    PATH=/opt/venv/bin:/opt/ik_llama.cpp/build/bin:${PATH}

SHELL ["/bin/bash", "-o", "pipefail", "-c"]

RUN apt-get update && apt-get install -y --no-install-recommends \
      build-essential \
      ca-certificates \
      cmake \
      curl \
      git \
      libcurl4-openssl-dev \
      libgomp1 \
      python3 \
      python3-pip \
      python3-venv \
      pkg-config \
    && rm -rf /var/lib/apt/lists/*

RUN python3 -m venv /opt/venv && \
    /opt/venv/bin/pip install --upgrade pip setuptools wheel && \
    /opt/venv/bin/pip install \
      --index-url https://download.pytorch.org/whl/cpu \
      torch && \
    /opt/venv/bin/pip install \
      "transformers==${TRANSFORMERS_VERSION}" \
      "peft==0.18.1" \
      "accelerate" \
      "safetensors" \
      "huggingface_hub" \
      "sentencepiece" \
      "protobuf" \
      "numpy"

RUN git clone https://github.com/ikawrakow/ik_llama.cpp /opt/ik_llama.cpp && \
    cd /opt/ik_llama.cpp && \
    git checkout --detach "${IK_LLAMA_REF}" && \
    cmake -S . -B build \
      -DGGML_NATIVE=ON \
      -DGGML_CUDA=ON \
      -DCMAKE_CUDA_ARCHITECTURES="${CMAKE_CUDA_ARCHITECTURES}" \
      -DBUILD_SHARED_LIBS=OFF \
      -DLLAMA_BUILD_SERVER=ON \
      -DLLAMA_BUILD_TESTS=OFF && \
    cmake --build build --config Release -j"$(nproc)"

WORKDIR /workspace

FROM base AS tools

CMD ["bash"]

FROM base AS server

CMD ["bash"]
