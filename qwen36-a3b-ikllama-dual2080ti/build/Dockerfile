# syntax=docker/dockerfile:1

ARG CUDA_VERSION=12.8.1

FROM nvidia/cuda:${CUDA_VERSION}-devel-ubuntu24.04 AS base

ARG DEBIAN_FRONTEND=noninteractive
ARG CMAKE_CUDA_ARCHITECTURES=75
ARG IK_LLAMA_REPO=https://github.com/ikawrakow/ik_llama.cpp
ARG IK_LLAMA_REF=main

ENV PIP_NO_CACHE_DIR=1 \
    PYTHONUNBUFFERED=1 \
    PATH=/opt/venv/bin:/opt/ik_llama.cpp/build/bin:${PATH} \
    LIBRARY_PATH=/usr/local/cuda/lib64/stubs:/usr/local/cuda/targets/x86_64-linux/lib/stubs:${LIBRARY_PATH} \
    HF_HOME=/root/.cache \
    HF_HUB_CACHE=/root/.cache/huggingface \
    TRANSFORMERS_CACHE=/root/.cache/huggingface

SHELL ["/bin/bash", "-o", "pipefail", "-c"]

RUN apt-get update && apt-get install -y --no-install-recommends \
      build-essential \
      ca-certificates \
      cmake \
      curl \
      git \
      libcurl4-openssl-dev \
      libgomp1 \
      ninja-build \
      python3 \
      python3-pip \
      python3-venv \
      pkg-config \
    && rm -rf /var/lib/apt/lists/*

RUN python3 -m venv /opt/venv && \
    /opt/venv/bin/pip install --upgrade pip setuptools wheel && \
    /opt/venv/bin/pip install \
      huggingface_hub \
      requests \
      tqdm

RUN ln -sf /usr/local/cuda/lib64/stubs/libcuda.so /usr/local/cuda/lib64/stubs/libcuda.so.1 && \
    ln -sf /usr/local/cuda/targets/x86_64-linux/lib/stubs/libcuda.so /usr/local/cuda/targets/x86_64-linux/lib/stubs/libcuda.so.1

WORKDIR /opt/ik_llama.cpp
COPY third_party/ik_llama.cpp /opt/ik_llama.cpp

RUN cmake -S . -B build -G Ninja \
      -DGGML_CUDA=ON \
      -DCMAKE_BUILD_TYPE=Release \
      -DCMAKE_CUDA_ARCHITECTURES="${CMAKE_CUDA_ARCHITECTURES}" \
      -DBUILD_SHARED_LIBS=ON \
      -DLLAMA_BUILD_SERVER=ON \
      -DLLAMA_BUILD_TESTS=OFF \
      -DLLAMA_CURL=ON \
      -DCMAKE_EXE_LINKER_FLAGS="-Wl,-rpath-link,/usr/local/cuda/lib64/stubs -Wl,-rpath-link,/usr/local/cuda/targets/x86_64-linux/lib/stubs" \
      -DCMAKE_SHARED_LINKER_FLAGS="-Wl,-rpath-link,/usr/local/cuda/lib64/stubs -Wl,-rpath-link,/usr/local/cuda/targets/x86_64-linux/lib/stubs" \
      -DCMAKE_C_FLAGS="-fPIC -mcmodel=large" \
      -DCMAKE_CXX_FLAGS="-fPIC -mcmodel=large" && \
    cmake --build build --target llama-server -j"$(nproc)"

WORKDIR /workspace

FROM base AS tools
CMD ["bash"]

FROM base AS server
CMD ["bash"]
