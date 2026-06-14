#!/usr/bin/env bash
set -euo pipefail

script_dir="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)"
project_dir="$(CDPATH= cd -- "${script_dir}/.." && pwd)"

source "$script_dir/common.sh"

os_id=""
os_version=""
if [ -r /etc/os-release ]; then
  # shellcheck disable=SC1091
  . /etc/os-release
  os_id="${ID:-}"
  os_version="${VERSION_ID:-}"
fi

if [ "$os_id" != "ubuntu" ] || { [ "$os_version" != "22.04" ] && [ "$os_version" != "24.04" ]; }; then
  die "This script only supports Ubuntu 22.04/24.04. Detected: ${os_id:-unknown} ${os_version:-unknown}"
fi

if [ "$(id -u)" -eq 0 ]; then
  apt_cmd=(apt-get)
else
  require_command sudo
  apt_cmd=(sudo apt-get)
fi

printf 'Installing base dependencies on Ubuntu %s...\n' "$os_version"
"${apt_cmd[@]}" update
"${apt_cmd[@]}" install -y --no-install-recommends \
  build-essential \
  ca-certificates \
  cmake \
  curl \
  git \
  jq \
  python3 \
  python3-pip \
  wget

require_command python3
require_command pip3

if ! python3 -m pip show huggingface_hub >/dev/null 2>&1; then
  printf 'Installing huggingface_hub for the current user...\n'
  python3 -m pip install --user --upgrade huggingface_hub
else
  printf 'huggingface_hub already available.\n'
fi

if command -v nvidia-smi >/dev/null 2>&1; then
  printf 'NVIDIA GPU detected:\n'
  nvidia-smi -L || true
  printf 'Reminder: this deployment also needs Docker Engine, Docker Compose, and the NVIDIA Container Toolkit.\n'
else
  printf 'No NVIDIA GPU detected on this host.\n'
  printf 'The build/start scripts will fail until an NVIDIA driver and CUDA-capable GPU are available.\n'
fi

if command -v docker >/dev/null 2>&1 || command -v docker-compose >/dev/null 2>&1; then
  printf 'Docker / Compose commands detected.\n'
else
  printf 'Docker / Compose commands were not detected.\n'
  printf 'Install Docker Engine + Docker Compose before running build/start scripts.\n'
fi

printf 'Dependency installation finished.\n'
printf 'Project directory: %s\n' "$project_dir"
