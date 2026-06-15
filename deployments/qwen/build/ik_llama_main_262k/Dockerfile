FROM nvidia/cuda:13.0.1-devel-ubuntu24.04

ARG IK_LLAMA_CPP_REPO=https://github.com/ikawrakow/ik_llama.cpp.git
ARG IK_LLAMA_CPP_REF=main
ARG CUDA_ARCHITECTURES=75

ENV DEBIAN_FRONTEND=noninteractive
ENV HF_HUB_ENABLE_HF_TRANSFER=0
ENV HF_VENV=/opt/hf-venv
ENV CUDA_STUBS=/usr/local/cuda/lib64/stubs
ENV LIBRARY_PATH=/usr/local/cuda/lib64/stubs
ENV PATH="${HF_VENV}/bin:${PATH}"

RUN apt-get update \
    && apt-get install -y --no-install-recommends \
        build-essential \
        ca-certificates \
        cmake \
        curl \
        git \
        jq \
        libcurl4-openssl-dev \
        ninja-build \
        pkg-config \
        python3 \
        python3-pip \
        python3-venv \
    && rm -rf /var/lib/apt/lists/*

RUN python3 -m venv "${HF_VENV}" \
    && "${HF_VENV}/bin/python" -m pip install --no-cache-dir -U pip setuptools wheel \
    && "${HF_VENV}/bin/python" -m pip install --no-cache-dir -U "huggingface_hub<1.0" hf_xet \
    && huggingface-cli --help >/dev/null

RUN ln -sf libcuda.so "${CUDA_STUBS}/libcuda.so.1" \
    && ln -sf libcuda.so /usr/local/cuda/targets/x86_64-linux/lib/stubs/libcuda.so.1

RUN git clone --recursive "${IK_LLAMA_CPP_REPO}" /opt/ik_llama.cpp \
    && cd /opt/ik_llama.cpp \
    && git checkout "${IK_LLAMA_CPP_REF}" \
    && git submodule update --init --recursive \
    && cmake -B build -G Ninja \
        -DGGML_CUDA=ON \
        -DGGML_NATIVE=ON \
        -DGGML_CUDA_FA=ON \
        -DCMAKE_BUILD_TYPE=Release \
        -DCMAKE_CUDA_ARCHITECTURES="${CUDA_ARCHITECTURES}" \
        -DCMAKE_EXE_LINKER_FLAGS="-Wl,-rpath-link,${CUDA_STUBS}" \
        -DCMAKE_SHARED_LINKER_FLAGS="-Wl,-rpath-link,${CUDA_STUBS}" \
    && cmake --build build --target llama-server -j"$(nproc)" \
    && test -x /opt/ik_llama.cpp/build/bin/llama-server

COPY start-main-262k.sh /usr/local/bin/start-main-262k.sh
RUN chmod +x /usr/local/bin/start-main-262k.sh

EXPOSE 8080

ENTRYPOINT ["/usr/local/bin/start-main-262k.sh"]
