#!/usr/bin/env bash
set -euo pipefail

script_dir="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)"
project_dir="$(CDPATH= cd -- "${script_dir}/.." && pwd)"

source "$script_dir/common.sh"
load_env_sources
setup_logging "$(basename "$0" .sh)"

repo_url="${IK_LLAMA_REPO:-https://github.com/ikawrakow/ik_llama.cpp}"
repo_ref="${IK_LLAMA_REF:-main}"
target_dir="$project_dir/third_party/ik_llama.cpp"

if [ -d "$target_dir/.git" ]; then
  printf 'ik_llama.cpp already present at %s\n' "$target_dir"
  printf 'Current commit: '
  git -C "$target_dir" rev-parse --short HEAD || true
  exit 0
fi

mkdir -p "$project_dir/third_party"
printf 'Cloning ik_llama.cpp from %s (%s)\n' "$repo_url" "$repo_ref"
git clone --depth 1 --branch "$repo_ref" "$repo_url" "$target_dir"
printf 'ik_llama.cpp checked out at %s\n' "$target_dir"
