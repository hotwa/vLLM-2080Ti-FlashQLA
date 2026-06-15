#!/usr/bin/env bash
set -euo pipefail

script_dir="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)"
project_dir="$(CDPATH= cd -- "${script_dir}/.." && pwd)"

source "$script_dir/common.sh"
load_env_sources
setup_logging "$(basename "$0" .sh)"

out_file="${RESULTS_DIR:-$project_dir/results}/system_info.md"
mkdir -p "$(dirname "$out_file")"

{
  echo "# System Info"
  echo
  echo "Generated: $(date -Iseconds)"
  echo
  echo "## Host"
  echo '```'
  uname -a
  echo '```'
  echo
  echo "## OS"
  echo '```'
  cat /etc/os-release
  echo '```'
  echo
  echo "## CPU"
  echo '```'
  lscpu
  echo '```'
  echo
  echo "## Memory"
  echo '```'
  free -h
  echo '```'
  echo
  echo "## NVIDIA"
  echo '```'
  nvidia-smi
  echo '```'
  echo
  echo "## NVIDIA Topology"
  echo '```'
  nvidia-smi topo -m || true
  echo '```'
  echo
  echo "## Docker"
  echo '```'
  docker version
  echo '```'
  echo
  echo "## Docker Compose"
  echo '```'
  docker compose version
  echo '```'
  echo
  echo "## Git"
  echo '```'
  git -C "$project_dir" rev-parse --short HEAD 2>/dev/null || true
  echo '```'
} > "$out_file"

printf 'System info written to %s\n' "$out_file"
