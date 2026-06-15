# syntax=docker/dockerfile:1

ARG CUDA_VERSION=12.8.1

FROM nvidia/cuda:${CUDA_VERSION}-devel-ubuntu24.04 AS builder

ARG DEBIAN_FRONTEND=noninteractive
# RTX 5090 = Blackwell = sm_120
ARG CMAKE_CUDA_ARCHITECTURES=120
ARG IK_LLAMA_REPO=https://github.com/ikawrakow/ik_llama.cpp
ARG IK_LLAMA_REF=main

# 代理配置（构建时可选，通过 --build-arg 注入）
ARG PROXY_URL=
ENV HTTPS_PROXY=${PROXY_URL} \
    HTTP_PROXY=${PROXY_URL} \
    ALL_PROXY=${PROXY_URL} \
    NO_PROXY=localhost,127.0.0.1,::1 \
    https_proxy=${PROXY_URL} \
    http_proxy=${PROXY_URL} \
    all_proxy=${PROXY_URL} \
    no_proxy=localhost,127.0.0.1,::1

ENV PIP_NO_CACHE_DIR=1 \
    PYTHONUNIVERSE=1 \
    PATH=/opt/ik_llama.cpp/build/bin:${PATH}

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
      pkg-config \
      python3 \
      python3-pip \
      wget \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /opt/ik_llama.cpp
RUN git clone https://github.com/ikawrakow/ik_llama.cpp /opt/ik_llama.cpp
# COPY repos/ik_llama.cpp /opt/ik_llama.cpp

RUN cmake -S . -B build -G Ninja \
      -DGGML_CUDA=ON \
      -DCMAKE_BUILD_TYPE=Release \
      -DCMAKE_CUDA_ARCHITECTURES="${CMAKE_CUDA_ARCHITECTURES}" \
      -DBUILD_SHARED_LIBS=ON \
      -DLLAMA_BUILD_EXAMPLES=ON \
      -DLLAMA_BUILD_SERVER=ON \
      -DLLAMA_BUILD_TESTS=OFF \
      -DLLAMA_CURL=ON \
      -DCMAKE_EXE_LINKER_FLAGS=-Wl,--allow-shlib-undefined \
    && cmake --build build --target llama-server -j"$(nproc)"

FROM builder AS server
WORKDIR /workspace
CMD ["bash"]
