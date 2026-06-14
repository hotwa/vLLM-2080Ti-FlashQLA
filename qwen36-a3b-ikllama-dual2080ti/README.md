# qwen36-a3b-ikllama-dual2080ti

This project deploys `ik_llama.cpp` as a local server on the dual RTX 2080 Ti
22GB NVLink host.

The current local GGUF set under `models/gguf` is:

- `Qwen3.6-35B-A3B-Opus-Q5_K_M.gguf`
- `Qwen3.6-35B-A3B-Opus-Q4_K_S.gguf`
- `Qwen3.6-35B-A3B-UD-Q5_K_M.gguf`

The Opus GGUFs were downloaded from `rico03/Qwen3.6-35B-Opus-Reasoning-GGUF`,
not uploaded from this workspace. The legacy `UD-Q5_K_M` file remains locally
for comparison, but it is no longer the primary file this setup documents.

The goal is to keep the deployment reproducible, long-context friendly, and
easy to re-run for 16k / 32k / 64k comparisons.

## What this project contains

- Docker-based `ik_llama.cpp` build and runtime
- Hugging Face token discovery and safe model download
- deterministic prompt generation for benchmark sweeps
- healthcheck, smoke test, and result collection scripts
- markdown and CSV outputs under `results/`

## Runtime selection

The scripts prefer the project-local `ik_llama.cpp` build output at
`third_party/ik_llama.cpp/build-qwen36-2080ti/bin/llama-server`. The system
`llama-server` shipped on this host was too old for `qwen35moe` and failed to
load this model, so the project now builds and uses its own binary by default.
For persistence in this workspace the host runtime is launched inside a
detached `tmux` session. Docker remains available as a fallback path if you
explicitly opt into it.

## Model selection

For the current local setup, point `MODEL_FILE` at
`Qwen3.6-35B-A3B-Opus-Q5_K_M.gguf` by default. Use
`Qwen3.6-35B-A3B-Opus-Q4_K_S.gguf` when you want the smaller fallback.
`Qwen3.6-35B-A3B-UD-Q5_K_M.gguf` is still on disk as a legacy comparison file.

## Recommended starting profile

The launch profile below is tuned for the current local GGUF metadata template,
the Opus Q5 local model, and a 128k validation gate. In this project,
`JINJA=0` means "use the template embedded in the GGUF metadata" and
`JINJA=1` means "force the external template file under `jinja/`":

- `MAX_MODEL_LEN=131072`
- `N_PARALLEL=1`
- `REASONING_BUDGET=0`
- `JINJA=0`
- `CHAT_TEMPLATE_ENABLE_THINKING=0`
- `SAMPLING_TEMP=0.7`
- `SAMPLING_TOP_P=0.8`
- `SAMPLING_TOP_K=20`
- `SAMPLING_MIN_P=0.0`
- `SAMPLING_PRESENCE_PENALTY=1.5`
- `SPLIT_MODE=graph`
- `TENSOR_SPLIT=50,50`
- `N_GPU_LAYERS=999`
- `CACHE_TYPE_K=q8_0`
- `CACHE_TYPE_V=q8_0`
- `UBATCH=512`
- `BATCH=2048`
- `FLASH_ATTN=1`
- `NO_MMAP=1`
- `REASONING_FORMAT=none`

This profile prioritizes stability and long-context usability on SM75 cards.
It now uses the chat template embedded in the GGUF metadata by default. The
custom OpenCode-friendly `qwopus_v3` template remains in `jinja/` for manual
experiments, but it is no longer the default launch path.

### Tool-calling note

The current OpenClaw/OpenCode-facing setup works with the server exposed on
port `8000`. The clean baseline is:

- the Opus `Q5_K_M` GGUF
- `JINJA=0` for the model's embedded template
- the OpenAI-compatible `/v1/chat/completions` endpoint

If an external agent starts looping on tool calls, check the client first for
extra protocol markers, stale tool-message replay, or a plugin layer such as
DCP injecting synthetic message metadata. The server-side `tools` flow itself
is healthy.

## Alternative profiles

See [`configs/profiles.json`](./configs/profiles.json) for the three canonical
profiles used by this project:

- `stable`
- `aggressive`
- `fallback`

## Quick start

1. Create a local `.env` from `.env.example`.
2. Run `./scripts/setup_env.sh`.
3. Run `./scripts/download_model.sh`.
4. Run `./scripts/fetch_ik_llama.sh`.
5. Run `./scripts/build.sh` to build the local `ik_llama.cpp` binary.
6. Run `./scripts/start.sh`.
7. Run `./scripts/healthcheck.sh`.
8. Run `./scripts/test_model.sh`.
9. Run `./scripts/benchmark.sh`.

## Output files

The following files are generated under `results/`:

- `download_report.md`
- `system_info.md`
- `config_notes.md`
- `benchmark_raw.csv`
- `benchmark_summary.md`

## Notes on token handling

The download workflow checks, in order:

- `HF_TOKEN`
- `HUGGINGFACE_TOKEN`
- `HUGGING_FACE_HUB_TOKEN`
- the local ignored `.env`
- `../CoPaw/.env` in this workspace, if present
- Hugging Face CLI authentication state

If no token is available and the model is gated, the download script stops and
asks for a token instead of writing anything sensitive into tracked files.

## Notes on local build

- `./scripts/build.sh` now builds `ik_llama.cpp` locally by default.
- Set `BUILD_BACKEND=docker` only if you explicitly want the Docker fallback.
- The local build is compiled for `sm75` (`CMAKE_CUDA_ARCHITECTURES=75`).
