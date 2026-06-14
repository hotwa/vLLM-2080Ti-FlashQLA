#!/usr/bin/env bash
set -euo pipefail

script_dir="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)"
project_dir="$(CDPATH= cd -- "${script_dir}/.." && pwd)"

source "$script_dir/common.sh"
load_env_sources
ensure_project_dirs

cd "$project_dir"

require_command git
require_command python3
require_command curl
require_nvidia_gpu

repo_dir="$project_dir/repos/ik_llama.cpp"
repo_url="${IK_LLAMA_REPO:-https://github.com/ikawrakow/ik_llama.cpp}"
repo_ref="${IK_LLAMA_REF:-main}"
image_name="qwopus-glm18b-ikllama-server:${repo_ref}"

if [ ! -d "$repo_dir/.git" ]; then
  printf 'Cloning ik_llama.cpp into %s...\n' "$repo_dir"
  git clone --depth 1 --branch "$repo_ref" "$repo_url" "$repo_dir"
else
  if [ -n "$(git -C "$repo_dir" status --porcelain)" ]; then
    die "The repository at $repo_dir has local changes. Please clean it up before building."
  fi
  current_url="$(git -C "$repo_dir" remote get-url origin)"
  if [ "$current_url" != "$repo_url" ]; then
    printf 'Updating origin URL for %s...\n' "$repo_dir"
    git -C "$repo_dir" remote set-url origin "$repo_url"
  fi
  printf 'Updating ik_llama.cpp in %s...\n' "$repo_dir"
  git -C "$repo_dir" fetch --tags origin "$repo_ref"
  git -C "$repo_dir" checkout "$repo_ref"
  git -C "$repo_dir" pull --ff-only origin "$repo_ref"
fi

arch="${CMAKE_CUDA_ARCHITECTURES:-}"
if [ -z "$arch" ]; then
  arch="$(detect_cuda_arch)"
  export CMAKE_CUDA_ARCHITECTURES="$arch"
fi

printf 'Using CUDA architecture: %s\n' "$arch"
printf 'Building Docker image: %s\n' "$image_name"

compose_cmd config --quiet
compose_cmd build --pull server

server_bin="$(docker_cmd run --rm --entrypoint bash "$image_name" -lc 'command -v llama-server')"
if [ -z "$server_bin" ]; then
  die "llama-server was not found in the built image."
fi

printf 'llama-server binary: %s\n' "$server_bin"
