#!/usr/bin/env bash
set -euo pipefail

script_dir="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)"
project_dir="$(CDPATH= cd -- "${script_dir}/.." && pwd)"

source "$script_dir/common.sh"
load_env_sources
setup_logging "$(basename "$0" .sh)"

build_backend="${BUILD_BACKEND:-local}"

if [ ! -d "$project_dir/third_party/ik_llama.cpp/.git" ]; then
  printf 'ik_llama.cpp source is missing; fetching it first.\n'
  "$script_dir/fetch_ik_llama.sh"
fi

if [ "$build_backend" = "docker" ]; then
  printf 'Building server image with Docker Compose...\n'
  docker compose --project-directory "$project_dir" -f "$project_dir/docker-compose.yml" config --quiet
  docker compose --project-directory "$project_dir" -f "$project_dir/docker-compose.yml" build server
  printf 'Docker build finished.\n'
  exit 0
fi

src_dir="$(ik_llama_source_dir)"
build_dir="$(ik_llama_build_dir)"
cuda_arch="${CMAKE_CUDA_ARCHITECTURES:-${CUDA_ARCHITECTURES:-75}}"
llama_curl="${LLAMA_CURL:-OFF}"
build_jobs="${BUILD_JOBS:-8}"

mkdir -p "$build_dir"

printf 'Building ik_llama.cpp locally...\n'
cmake -S "$src_dir" -B "$build_dir" -G Ninja \
  -DGGML_CUDA=ON \
  -DGGML_NATIVE=ON \
  -DCMAKE_BUILD_TYPE="${CMAKE_BUILD_TYPE:-Release}" \
  -DCMAKE_CUDA_ARCHITECTURES="$cuda_arch" \
  -DBUILD_SHARED_LIBS=ON \
  -DLLAMA_CURL="$llama_curl"
cmake --build "$build_dir" -j"$build_jobs" --target llama-server llama-cli llama-bench
printf 'Local build finished: %s\n' "$build_dir/bin/llama-server"
