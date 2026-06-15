# Qwen3.6-27B ik_llama.cpp Main-Only 262K on 2x RTX 2080 Ti

This is the production-oriented deployment path after local testing showed MTP is slower on this 2 x RTX 2080 Ti 22GB NVLink machine.

## Service

- Compose: `qwen/docker-compose.2080ti-ik-main-262k.yml`
- Image: `local/ik-llama-cpp:qwen36-main-262k-cuda`
- Container: `qwen36-27b-ik-main-262k`
- Host port: `8080`
- API: OpenAI-compatible `llama-server`
- Model: `/models/Qwen3.6-27B-Q4_K_M.gguf`
- Context: `262144`
- MTP: disabled

## Default Runtime Parameters

```text
CUDA_VISIBLE_DEVICES=1,0
NVIDIA_VISIBLE_DEVICES=1,0
CTX_SIZE=262144
SPLIT_MODE=graph
TENSOR_SPLIT=40,60
BATCH_SIZE=256
UBATCH_SIZE=128
FLASH_ATTN=on
N_GPU_LAYERS=999
EXTRA_ARGS=--cache-ram 0
```

The `CUDA_VISIBLE_DEVICES=1,0` and `TENSOR_SPLIT=40,60` combination was chosen because the second physical GPU was hotter and throttled more often in local testing. Reversing the CUDA order moves the heavier logical CUDA1/output-layer work onto the cooler physical GPU0.

## Build

```bash
docker compose -f qwen/docker-compose.2080ti-ik-main-262k.yml build
```

## Start

```bash
docker compose -f qwen/docker-compose.2080ti-ik-main-262k.yml up -d
```

## Stop

```bash
docker compose -f qwen/docker-compose.2080ti-ik-main-262k.yml down
```

## Logs

```bash
docker logs -f qwen36-27b-ik-main-262k
```

Useful startup lines:

```text
llama_init_from_model: n_ctx         = 262144
llama_init_from_model: KV self size  = 16384.00 MiB
slot         init: id  0 | task -1 | speculative decoding context not initialized
INFO [                    main] HTTP server listening ... port="8080"
```

The `speculative decoding context not initialized` line confirms MTP/speculative decoding is not enabled.

## Test

```bash
curl -fsS http://127.0.0.1:8080/health

curl -fsS http://127.0.0.1:8080/v1/models | jq

curl -s http://127.0.0.1:8080/v1/chat/completions \
  -H 'Content-Type: application/json' \
  -d '{
    "model": "Qwen3.6-27B",
    "messages": [
      {"role": "user", "content": "Write a concise Python binary search function, no explanation."}
    ],
    "temperature": 0.2,
    "max_tokens": 256,
    "stop": ["<|im_end|>", "<|endoftext|>"]
  }' | jq
```

Or run the bundled test script:

```bash
qwen/test-ik-main-262k.sh
```

## Verified Local Result

After deployment, `/v1/models` returned:

```text
id = Qwen3.6-27B
max_model_len = 262144
```

The smoke chat request completed with:

```text
completion_tokens = 94
n_ctx = 262144
predicted_per_second = 36.88 tok/s
```

## Notes

- The Qwen chat template may still emit an empty `<think></think>` block even with `--reasoning off` and `enable_thinking=false`. This is cosmetic and can be stripped client-side if needed.
- If speed drops sharply, check GPU temperature and throttling:

```bash
nvidia-smi --query-gpu=index,temperature.gpu,clocks.sm,utilization.gpu,clocks_throttle_reasons.active,clocks_throttle_reasons.hw_slowdown --format=csv,noheader,nounits
```

- If port `8080` conflicts, start with another host port:

```bash
QWEN_IK_MAIN_HOST_PORT=8082 docker compose -f qwen/docker-compose.2080ti-ik-main-262k.yml up -d
```

## Cleanup Rationale

The following experimental DFlash compose files were intentionally not kept:

```text
qwen/docker-compose.2080dflash.yml
qwen/docker-compose.2080dflash.dual-row.yml
qwen/docker-compose.buun-dflash.yml
```

Reasons:

- They target the earlier `spiritbuun/buun-llama-cpp` DFlash speculative path, not the final `ik_llama.cpp` main-only path.
- The tested DFlash/MTP-style speculative routes were slower than main-only on this 2 x RTX 2080 Ti machine.
- The DFlash dual-GPU path had stability risks in multi-GPU layer/pipeline synchronization during earlier testing.
- Keeping multiple 2080Ti Qwen3.6 compose files with different split modes, model aliases, and speculative settings makes accidental deployment of the slower path more likely.

The retained production compose is:

```text
qwen/docker-compose.2080ti-ik-main-262k.yml
```

Experimental DFlash build scripts, DFlash test scripts, and MTP GGUF POC conversion files are also not part of this production deployment commit. They were useful for investigation, but the verified result for this machine is that MTP/DFlash did not improve throughput and added operational ambiguity.

For this machine, the best verified deployment is `ik_llama.cpp` main-only with `CTX_SIZE=262144`, `SPLIT_MODE=graph`, `TENSOR_SPLIT=40,60`, `CUDA_VISIBLE_DEVICES=1,0`, `BATCH_SIZE=256`, `UBATCH_SIZE=128`, and Flash Attention enabled.
