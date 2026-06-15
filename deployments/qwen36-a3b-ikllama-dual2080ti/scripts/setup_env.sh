#!/usr/bin/env bash
set -euo pipefail

script_dir="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)"
project_dir="$(CDPATH= cd -- "${script_dir}/.." && pwd)"

source "$script_dir/common.sh"
load_env_sources
setup_logging "$(basename "$0" .sh)"

write_env=1
for arg in "$@"; do
  case "$arg" in
    --check-only)
      write_env=0
      ;;
    --no-write)
      write_env=0
      ;;
  esac
done

ensure_venv

token_source=""
if token_source="$(resolve_hf_token_source 2>/dev/null)"; then
  printf 'HF token source detected: %s\n' "$token_source"
else
  printf 'No HF token source detected.\n'
fi

token=""
if token="$(resolve_hf_token 2>/dev/null)"; then
  printf 'HF token value is available for runtime use.\n'
else
  printf 'HF token value is not available.\n'
fi

env_file="$project_dir/.env"
if [ "$write_env" -eq 1 ] && [ ! -f "$env_file" ]; then
  cp "$project_dir/.env.example" "$env_file"
  if [ -n "$token" ]; then
    python3 - "$env_file" "$token" <<'PY'
from pathlib import Path
import sys

env_file = Path(sys.argv[1])
token = sys.argv[2]
lines = env_file.read_text(encoding="utf-8").splitlines()
updated = []
seen = False
for line in lines:
    if line.startswith("HF_TOKEN="):
        updated.append(f"HF_TOKEN={token}")
        seen = True
    else:
        updated.append(line)
if not seen:
    updated.append(f"HF_TOKEN={token}")
env_file.write_text("\n".join(updated) + "\n", encoding="utf-8")
PY
  fi
  chmod 600 "$env_file"
  printf 'Created %s\n' "$env_file"
elif [ "$write_env" -eq 1 ]; then
  printf '%s already exists; leaving it unchanged.\n' "$env_file"
fi

printf 'Setup complete.\n'
