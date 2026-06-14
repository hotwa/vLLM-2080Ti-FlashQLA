# Config Notes

## Local GGUF inventory

- Preferred local model: `Qwen3.6-35B-A3B-Opus-Q5_K_M.gguf`
- Smaller fallback: `Qwen3.6-35B-A3B-Opus-Q4_K_S.gguf`
- Legacy local comparison file: `Qwen3.6-35B-A3B-UD-Q5_K_M.gguf`
- Source repo for the Opus files: `rico03/Qwen3.6-35B-Opus-Reasoning-GGUF`

## Current runtime state

- Host runtime: project-local `ik_llama.cpp`
- Served model: `Qwen3.6-35B-A3B-Opus-Q5_K_M`
- Default template mode: `JINJA=0`
- Meaning of `JINJA=0`: use the template embedded in the GGUF metadata
- Meaning of `JINJA=1`: force the external template file under `jinja/`
- Current endpoint: `http://127.0.0.1:8000/v1`
- The service is currently healthy and serving the Opus Q5 model

## Runtime selection

- Preferred runtime: project-local `third_party/ik_llama.cpp/build-qwen36-2080ti/bin/llama-server`
- System `llama-server` at `/usr/local/bin/llama-server` is too old for this
  model and fails with `unknown model architecture: 'qwen35moe'`
- Host runtime is kept alive with a detached `tmux` session so the process
  survives command completion in this workspace
- Docker fallback: retained in `docker-compose.yml` and `build.sh`, but not
  required for the main execution path in this workspace
- The local source tree already includes `qwen35moe` support in
  `src/llama-arch.cpp` and `src/llama-load-tensors.cpp`

## Stable profile

- `MODEL_FILE=Qwen3.6-35B-A3B-Opus-Q5_K_M.gguf`
- `MAX_MODEL_LEN=131072`
- `SPLIT_MODE=graph`
- `TENSOR_SPLIT=50,50`
- `N_PARALLEL=1`
- `N_GPU_LAYERS=999`
- `UBATCH=512`
- `BATCH=2048`
- `CACHE_TYPE_K=q8_0`
- `CACHE_TYPE_V=q8_0`
- `NO_MMAP=1`
- `MLA_USE=3`
- `ATTENTION_MAX_BATCH=256`
- `REASONING_BUDGET=0`
- `CHAT_TEMPLATE_ENABLE_THINKING=0`
- `SAMPLING_TEMP=0.7`
- `SAMPLING_TOP_P=0.8`
- `SAMPLING_TOP_K=20`
- `SAMPLING_MIN_P=0.0`
- `SAMPLING_PRESENCE_PENALTY=1.5`
- `REASONING_TOKENS=none`

This is the recommended launch profile for first successful launch and the
128k gate when `MODEL_FILE` is set to the Opus Q5 file.
If you want the smaller retained GGUF, point `MODEL_FILE` at
`Qwen3.6-35B-A3B-Opus-Q4_K_S.gguf` instead.

## Agent/tool-call note

The current server-side `tools` flow is healthy. If OpenCode/OpenClaw loops on
`FileSystem.access`, `Get-Location`, or similar calls, the likely causes are on
the client side:

- DCP or a similar plugin injecting extra protocol markers
- tool results not being replayed back as proper `role=tool` messages
- a client-side parser reusing stale assistant/tool content

Use the Opus Q5 model with `JINJA=0` as the clean baseline when debugging this.
Only switch back to the external Jinja template when you explicitly want to
test that template path.

## Aggressive profile

- `MAX_MODEL_LEN=131072`
- `UBATCH=1024`
- `BATCH=4096`
- `NO_MMAP=1`
- `THREADS=6`

This profile increases host-side staging and batch size to see whether the model
can sustain higher throughput after the 128k gate is already passing.

## Fallback profile

- `MAX_MODEL_LEN=131072`
- `SPLIT_MODE=layer`
- `N_PARALLEL=1`
- `UBATCH=256`
- `BATCH=1024`
- `CACHE_TYPE_K=q4_0`
- `CACHE_TYPE_V=q4_0`
- `FLASH_ATTN=0`

This is the conservative "get it started" profile if the stable launch is too
close to memory limits.
