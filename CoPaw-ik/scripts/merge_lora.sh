#!/usr/bin/env bash
set -euo pipefail

script_dir="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)"
project_dir="$(CDPATH= cd -- "${script_dir}/.." && pwd)"

cd "$project_dir"

docker compose run --rm tools python3 - <<'PY'
import json
import os
import shutil
from pathlib import Path

import torch
from peft import PeftModel
from transformers import AutoModelForImageTextToText

base_model = Path(os.environ.get("BASE_MODEL_SOURCE", "/source/CoPaw/models/base/CoPaw-Flash-9B")).resolve()
lora_model = Path(os.environ.get("LORA_SOURCE", "/source/CoPaw/models/lora/CoPaw-Flash-9B-DataAnalyst-LoRA")).resolve()
merged_dir = Path(os.environ.get("MERGED_MODEL_DIR", "./models/merged/CoPaw-Flash-9B-DataAnalyst-Merged")).resolve()

required_base = [
    "config.json",
    "generation_config.json",
    "tokenizer.json",
    "tokenizer_config.json",
    "chat_template.jinja",
    "processor_config.json",
]
required_lora = ["adapter_config.json", "adapter_model.safetensors"]

missing = [str(base_model / name) for name in required_base if not (base_model / name).exists()]
missing += [str(lora_model / name) for name in required_lora if not (lora_model / name).exists()]
if missing:
    raise SystemExit("Missing required files:\n- " + "\n- ".join(missing))

if merged_dir.exists():
    shutil.rmtree(merged_dir)
merged_dir.mkdir(parents=True, exist_ok=True)

print(f"Loading base model from {base_model}")
model = AutoModelForImageTextToText.from_pretrained(
    base_model,
    trust_remote_code=True,
    torch_dtype=torch.float16,
    low_cpu_mem_usage=True,
    device_map="cpu",
)

print(f"Loading LoRA adapter from {lora_model}")
peft_model = PeftModel.from_pretrained(model, lora_model, is_trainable=False)
merged = peft_model.merge_and_unload()

if getattr(merged, "generation_config", None) is not None:
    for key in ("top_p", "min_p", "top_k"):
        if hasattr(merged.generation_config, key):
            setattr(merged.generation_config, key, None)

print(f"Saving merged model to {merged_dir}")
merged.save_pretrained(merged_dir, safe_serialization=True, max_shard_size="20GB")

for name in ["tokenizer.json", "tokenizer_config.json", "chat_template.jinja", "processor_config.json"]:
    src = base_model / name
    dst = merged_dir / name
    shutil.copy2(src, dst)

print("Merged model saved.")
print(json.dumps({"merged_dir": str(merged_dir)}, indent=2))
PY
