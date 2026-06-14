#!/usr/bin/env bash
set -euo pipefail

script_dir="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)"
project_dir="$(CDPATH= cd -- "${script_dir}/.." && pwd)"

cd "$project_dir"

docker compose run --rm \
  -e GGUF_BASENAME="${GGUF_BASENAME:-}" \
  -e GGUF_OUTTYPE="${GGUF_OUTTYPE:-}" \
  -e GGUF_QUANT="${GGUF_QUANT:-}" \
  -e LLAMA_CPP_REF="${LLAMA_CPP_REF:-}" \
  tools bash -lc '
  set -euo pipefail

  merged_dir="${MERGED_MODEL_DIR:-/workspace/models/merged/CoPaw-Flash-9B-DataAnalyst-Merged}"
  gguf_dir="${GGUF_DIR:-/workspace/models/gguf}"
  basename="${GGUF_BASENAME:-CoPaw-Flash-9B-DataAnalyst-Merged}"
  outtype="${GGUF_OUTTYPE:-f16}"
  quant="${GGUF_QUANT:-Q5_K_M}"
  quant_suffix="$(printf '%s' "$quant" | tr '[:upper:]' '[:lower:]')"
  llama_cpp_ref="${LLAMA_CPP_REF:-a279d0f0f4e746d1ef3429d8e9d02d2990b2daa7}"
  llama_cpp_dir="$(mktemp -d /tmp/llama.cpp.XXXXXX)"

  if [ ! -d "$merged_dir" ]; then
    echo "Merged model directory does not exist: $merged_dir" >&2
    echo "Run ./scripts/merge_lora.sh first." >&2
    exit 1
  fi

  mkdir -p "$gguf_dir"

  f16_file="$gguf_dir/${basename}-${outtype}.gguf"
  quant_file="$gguf_dir/${basename}-${quant_suffix}.gguf"

  trap "rm -rf \"$llama_cpp_dir\"" EXIT

  if [ ! -f "$f16_file" ]; then
    echo "Cloning official llama.cpp converter: $llama_cpp_ref"
    git clone https://github.com/ggml-org/llama.cpp "$llama_cpp_dir" >/dev/null
    git -C "$llama_cpp_dir" checkout --detach "$llama_cpp_ref" >/dev/null

    echo "Converting merged model to GGUF f16: $f16_file"
    python3 "$llama_cpp_dir/convert_hf_to_gguf.py" \
      "$merged_dir" \
      --outfile "$f16_file" \
      --outtype "$outtype"
  else
    echo "Reusing existing GGUF f16 file: $f16_file"
  fi

  if [ ! -f "$f16_file" ]; then
    echo "Missing intermediate GGUF file after conversion: $f16_file" >&2
    exit 1
  fi

  echo "Quantizing GGUF to: $quant_file"
  llama-quantize "$f16_file" "$quant_file" "$quant"

  echo "GGUF ready:"
  echo "$quant_file"
' \
