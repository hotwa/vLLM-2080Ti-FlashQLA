# CoPaw-ik llama.cpp Deployment

This folder is a separate `ik_llama.cpp` deployment for the existing CoPaw model:

- Base model: `agentscope-ai/CoPaw-Flash-9B`
- LoRA adapter: `jason1966/CoPaw-Flash-9B-DataAnalyst-LoRA`
- Published GGUF set: `Q5_K_M`, `Q4_K_S`, and `f16`

The workflow is:

1. Download or reuse the source base model and LoRA adapter with `./scripts/pull_models.sh`
2. Merge the LoRA into a local Hugging Face model directory
3. Convert the merged model to GGUF with the official `llama.cpp` converter
4. Quantize the GGUF for efficient inference
5. Serve the GGUF with `ik_llama.cpp` through Docker Compose

The runtime target here is text-first chat and tool calling. The model config is multimodal, but this first version is validated around chat / agent usage.

## Why this stack

`vLLM` is already working, but long-context throughput on Turing-class cards gets expensive. This deployment keeps the merged-model path but switches serving to `ik_llama.cpp`, while using the official `llama.cpp` converter for GGUF generation because the pinned `ik_llama.cpp` converter does not support this Qwen3.5 model class.

- quantized GGUF weights
- explicit multi-GPU split
- OpenAI-compatible server
- built-in function-call support
- Hugging Face upload helper for the published GGUF set

For this hardware, the default is deliberately conservative:

- `MAX_MODEL_LEN=262144`
- `N_PARALLEL=2`
- `SPLIT_MODE=layer`
- `CACHE_TYPE_K=q8_0`
- `CACHE_TYPE_V=q8_0`
- `GGUF_QUANT=Q5_K_M`

The runtime now validates the GGUF magic bytes before starting and falls back to the `Q4_K_S` or `f16` files if the `Q5_K_M` file is missing or corrupt.

`Q5_K_M` is the preferred quantization target because it is a practical balance between quality and memory pressure. If you want more headroom, change `GGUF_QUANT=Q4_K_S`. If the quantized file is corrupt, the startup script will fall back to the `Q4_K_S` or `f16` GGUF automatically.

## Folder Layout

```text
CoPaw-ik/
├─ .env.example
├─ .gitignore
├─ README.md
├─ docker-compose.yml
├─ build/
│  └─ Dockerfile
├─ hf-cache/
│  └─ .gitkeep
├─ models/
│  ├─ .gitkeep
│  ├─ gguf/
│  │  └─ .gitkeep
│  └─ merged/
│     └─ .gitkeep
└─ scripts/
   ├─ convert_to_gguf.sh
   ├─ healthcheck.sh
   ├─ merge_lora.sh
   ├─ pull_models.sh
   ├─ start.sh
   └─ test_model.sh
```

## Prerequisites

- Docker
- Docker Compose v2
- NVIDIA driver
- `nvidia-container-toolkit`

## First Run

1. Copy `.env.example` to `.env` and set `HF_TOKEN`.
2. If you still have the original CoPaw source tree locally, the merge scripts can reuse it.
   Otherwise `./scripts/pull_models.sh` will download the base model and LoRA adapter from Hugging Face.
3. Merge the adapter:

```bash
./scripts/merge_lora.sh
```

4. Convert and quantize to GGUF:

```bash
./scripts/convert_to_gguf.sh
```

The converter uses the official `ggml-org/llama.cpp` `convert_hf_to_gguf.py` script pinned by `LLAMA_CPP_REF` in `.env.example`.

5. Start the server:

```bash
./scripts/start.sh
```

6. Check health:

```bash
./scripts/healthcheck.sh
```

7. Run a small chat test:

```bash
./scripts/test_model.sh
```

## Serve Mode

This first version serves only the merged GGUF path. That is the right choice for `ik_llama.cpp` because it avoids runtime LoRA loading and keeps the serving stack deterministic.

The important distinction is:

- `CoPaw/` was the original direct-LoRA deployment source tree
- `CoPaw-ik/` is the merged-model GGUF deployment and upload workspace

## Recommended Defaults for 2x RTX 2080 Ti 22GB

- `MAX_MODEL_LEN=262144`
- `N_PARALLEL=2`
- `N_GPU_LAYERS=999`
- `SPLIT_MODE=layer`
- `TENSOR_SPLIT=1,1`
- `GGUF_QUANT=Q5_K_M`
- `CACHE_TYPE_K=q8_0`
- `CACHE_TYPE_V=q8_0`

These defaults prioritize stability and long-context support. If the first request is too slow, that is usually warmup, not a broken server.

## Tool Calling

The server is started with `--jinja` and the model chat template from the merged directory. The default runtime disables thinking by setting `REASONING_BUDGET=0` and passing `enable_thinking=false` to the chat template. If you do want reasoning output, set:

```bash
REASONING_BUDGET=-1
CHAT_TEMPLATE_ENABLE_THINKING=1
```

## Changing Context or Concurrency

For safer changes:

- Raise context in steps, not in one jump
- Keep `N_PARALLEL=2` until you have measured memory headroom
- If you need more throughput, try `GGUF_QUANT=Q4_K_S` before raising concurrency
- If you need higher quality, keep `Q5_K_M` and reduce concurrency

## Troubleshooting

### OOM

- Lower `N_PARALLEL` to `1`
- Switch `GGUF_QUANT` from `Q5_K_M` to `Q4_K_S`
- Keep `MAX_MODEL_LEN=262144` only if you actually need it

### LoRA merge fails

- Confirm the source model tree exists locally, or re-run `./scripts/pull_models.sh`
- Make sure `.env` has a real `HF_TOKEN`

### GGUF conversion fails

- Check that the merged Hugging Face directory exists
- If the model metadata changes upstream, bump `IK_LLAMA_REF`
- If the conversion script complains about model classes, the model may need a newer `ik_llama.cpp` commit

### Tool calling looks wrong

- Keep `--jinja` enabled
- Keep the chat template file copied into the merged model directory
- If the model starts emitting reasoning tags unexpectedly, try `REASONING_FORMAT=none`

## Publishing

Run `./scripts/publish_hf.sh --repo fanwe/CoPaw-Flash-9B-DataAnalyst-GGUF` to upload the published GGUF set to Hugging Face.
The upload helper publishes the three intended files:

- `CoPaw-Flash-9B-DataAnalyst-Merged-f16.gguf`
- `CoPaw-Flash-9B-DataAnalyst-Merged-q5_k_m.gguf`
- `CoPaw-Flash-9B-DataAnalyst-Merged-q4_k_s.gguf`

## Commands

Start:

```bash
./scripts/start.sh
```

Logs:

```bash
docker compose logs -f server
```

Health:

```bash
./scripts/healthcheck.sh
```

Test:

```bash
./scripts/test_model.sh
```

Stop:

```bash
docker compose down
```
