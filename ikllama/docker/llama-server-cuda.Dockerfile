# syntax=docker/dockerfile:1

ARG UBUNTU_VERSION=24.04
ARG CUDA_VERSION=13.0.1

# CUDA build image
ARG BASE_CUDA_DEV_CONTAINER=nvidia/cuda:${CUDA_VERSION}-devel-ubuntu${UBUNTU_VERSION}
# CUDA runtime image
ARG BASE_CUDA_RUN_CONTAINER=nvidia/cuda:${CUDA_VERSION}-runtime-ubuntu${UBUNTU_VERSION}

############################
# Build stage
############################
FROM ${BASE_CUDA_DEV_CONTAINER} AS build

# Target arch list for CMake CUDA architectures.
# Examples:
#   RTX 20xx: 75
#   RTX 30xx: 86
#   Hopper:   90
#   Blackwell:120 (only if your CUDA toolchain supports it)
ARG CUDA_DOCKER_ARCH="120"

RUN apt-get update && \
    apt-get install -y --no-install-recommends \
        build-essential \
        git \
        libcurl4-openssl-dev \
        ninja-build \
        cmake \
        ca-certificates \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /app
# COPY . .
ARG LLAMA_REF=main
RUN git clone --depth 1 --branch ${LLAMA_REF} https://ghproxy.dockless.eu.org/https://github.com/ikawrakow/ik_llama.cpp .
# Build-time envs
ENV CUDA_DOCKER_ARCH=${CUDA_DOCKER_ARCH}
ENV GGML_CUDA=1
ENV LLAMA_CURL=1
ENV LLAMA_ARG_HOST=0.0.0.0

# build stage only: satisfy link-time dependency on libcuda.so.1
RUN ln -sf /usr/local/cuda/lib64/stubs/libcuda.so /usr/local/cuda/lib64/stubs/libcuda.so.1 && \
    echo "/usr/local/cuda/lib64/stubs" > /etc/ld.so.conf.d/cuda-stubs.conf && \
    ldconfig

ENV LIBRARY_PATH=/usr/local/cuda/lib64/stubs:${LIBRARY_PATH}
ENV LD_LIBRARY_PATH=/usr/local/cuda/lib64/stubs:${LD_LIBRARY_PATH}


RUN cmake -S . -B build -G Ninja \
    -DGGML_CUDA=ON \
    -DCMAKE_BUILD_TYPE=Release \
    -DCMAKE_CUDA_ARCHITECTURES="${CUDA_DOCKER_ARCH}" \
    -DBUILD_SHARED_LIBS=ON \
    -DCMAKE_C_FLAGS="-fPIC -mcmodel=large" \
    -DCMAKE_CXX_FLAGS="-fPIC -mcmodel=large" \
 && cmake --build build --target llama-server llama-imatrix llama-quantize

############################
# Runtime stage
############################
FROM ${BASE_CUDA_RUN_CONTAINER} AS runtime

RUN apt-get update && \
    apt-get install -y --no-install-recommends \
        libcurl4 \
        libgomp1 \
        curl \
        ca-certificates \
    && rm -rf /var/lib/apt/lists/*

COPY --from=build /app/build/bin/llama-server /llama-server
COPY --from=build /app/build/bin/llama-imatrix /llama-imatrix
COPY --from=build /app/build/bin/llama-quantize /llama-quantize

# Shared libs produced by your build (paths may vary by repo layout; matches your original)
COPY --from=build /app/build/examples/mtmd/libmtmd.so /usr/local/lib/
COPY --from=build /app/build/ggml/src/libggml.so /usr/local/lib/
COPY --from=build /app/build/src/libllama.so /usr/local/lib/
RUN ldconfig

HEALTHCHECK CMD [ "curl", "-f", "http://localhost:8080/health" ]

ENTRYPOINT [ "/llama-server" ]