#!/usr/bin/env bash
set -euo pipefail

script_dir="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)"
project_dir="$(CDPATH= cd -- "${script_dir}/.." && pwd)"

source "$script_dir/common.sh"
load_env_sources
setup_logging "$(basename "$0" .sh)"

host_port="${HOST_PORT:-8000}"
curl -fsS "http://127.0.0.1:${host_port}/v1/models" >/dev/null
printf 'Healthcheck passed: /v1/models responded with HTTP 200.\n'
