#!/usr/bin/env bash
set -euo pipefail

script_dir="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)"
project_dir="$(CDPATH= cd -- "${script_dir}/.." && pwd)"

cd "$project_dir"

repo_id=""

while [ "$#" -gt 0 ]; do
  case "$1" in
    --repo)
      repo_id="${2:-}"
      shift 2
      ;;
    --help|-h)
      cat <<'EOF'
Usage: ./scripts/publish_hf.sh --repo fanwe/CoPaw-Flash-9B-DataAnalyst-GGUF
EOF
      exit 0
      ;;
    *)
      echo "Unknown argument: $1" >&2
      exit 1
      ;;
  esac
done

if [ -z "$repo_id" ]; then
  repo_id="${HF_PUBLISH_REPO:-}"
fi

if [ -z "$repo_id" ]; then
  echo "Missing Hugging Face target repo." >&2
  echo "Set HF_PUBLISH_REPO or pass --repo owner/name." >&2
  exit 1
fi

export HF_PUBLISH_REPO="$repo_id"

docker compose run --rm \
  -v "$project_dir:/workspace" \
  tools python3 /workspace/scripts/publish_hf.py --repo "$repo_id"
