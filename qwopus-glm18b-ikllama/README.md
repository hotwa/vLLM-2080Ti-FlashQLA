# qwopus-glm18b-ikllama

Docker Compose deployment for `ik_llama.cpp` serving the GGUF model
`Jackrong/Qwopus-GLM-18B-Merged-GGUF/Qwopus-GLM-18B-Healed-Q4_K_M.gguf`
behind an OpenAI-compatible API on `0.0.0.0:8080`.

## Layout

```text
.
├── README.md
├── .env.example
├── docker-compose.yml
├── build/
│   └── Dockerfile
├── scripts/
│   ├── common.sh
│   ├── install_deps.sh
│   ├── build_ik_llama.sh
│   ├── download_model.sh
│   ├── start_server.sh
│   ├── stop_server.sh
│   ├── healthcheck.sh
│   └── test_openai_compatible.sh
├── models/
├── repos/
├── logs/
└── run/
```

## Requirements

- Ubuntu 22.04 or 24.04
- NVIDIA driver installed and visible to `nvidia-smi`
- Docker Engine
- Docker Compose v2 plugin, or `docker-compose`
- NVIDIA Container Toolkit for `--gpus all`
- `git`, `curl`, `jq`, `python3`, `python3-pip`

If Docker commands require `sudo`, the scripts will use it when available.

## Quick Start

```bash
cd qwopus-glm18b-ikllama
cp .env.example .env
# Optional: set HF_TOKEN and/or API_KEY in .env before downloading or starting.
./scripts/install_deps.sh
./scripts/build_ik_llama.sh
./scripts/download_model.sh
./scripts/start_server.sh
./scripts/healthcheck.sh
./scripts/test_openai_compatible.sh
```

## Install Dependencies

`install_deps.sh` installs the host-side tools used by the project:

- `git`
- `build-essential`
- `cmake`
- `curl`
- `wget`
- `jq`
- `python3`
- `python3-pip`
- `huggingface_hub` Python package

It also checks for an NVIDIA GPU and prints a clear reminder that CUDA and the
NVIDIA driver must already be installed for the compose deployment to work.

## Download the Model

The model is downloaded to `./models/Qwopus-GLM-18B-Healed-Q4_K_M.gguf`.
The script supports `HF_TOKEN` from the environment or `.env`.
If you need an external Jinja template, set `JINJA=1` and `CHAT_TEMPLATE_FILE`
to a file mounted into the container.

```bash
./scripts/download_model.sh
```

If the file already exists and is larger than 1 GiB, the script skips it.

## Build the Server Image

`build_ik_llama.sh` clones or updates `ikawrakow/ik_llama.cpp` under
`./repos/ik_llama.cpp`, then builds the CUDA-enabled server image with Docker.
The script auto-detects a CUDA architecture from `nvidia-smi` when possible.

```bash
./scripts/build_ik_llama.sh
```

The resulting `llama-server` binary is built inside the image and verified after
the image finishes building.

## Start the Service

```bash
./scripts/start_server.sh
```

The script:

- loads `.env`
- validates the NVIDIA runtime
- ensures the model exists
- builds the image
- starts the compose service in the background
- writes runtime markers to `run/`
- writes logs to `logs/llama-server.log`

The service listens on:

- `http://0.0.0.0:8080`
- OpenAI-compatible base URL: `http://0.0.0.0:8080/v1`

## Stop the Service

```bash
./scripts/stop_server.sh
```

This stops the compose service and clears runtime marker files.

## Health Check

```bash
./scripts/healthcheck.sh
```

The health check verifies:

- the container is running
- the port is listening
- `GET /v1/models` responds successfully

## curl Examples

List models:

```bash
curl -fsS http://127.0.0.1:8080/v1/models | jq
```

Chat completion:

```bash
curl -fsS http://127.0.0.1:8080/v1/chat/completions \
  -H 'Content-Type: application/json' \
  -d '{
    "model": "Qwopus-GLM-18B-Healed-Q4_K_M",
    "messages": [
      {"role": "user", "content": "用中文简单介绍一下你自己"}
    ],
    "temperature": 0.7,
    "max_tokens": 128
  }' | jq
```

With `API_KEY` enabled:

```bash
curl -fsS http://127.0.0.1:8080/v1/chat/completions \
  -H 'Content-Type: application/json' \
  -H "Authorization: Bearer ${API_KEY}" \
  -d '{
    "model": "Qwopus-GLM-18B-Healed-Q4_K_M",
    "messages": [
      {"role": "user", "content": "用中文简单介绍一下你自己"}
    ],
    "temperature": 0.7,
    "max_tokens": 128
  }' | jq
```

## OpenAI-Compatible Client Config

For OpenClaw, OpenCode, or any other OpenAI-compatible client:

- Base URL: `http://服务器IP:8080/v1`
- API Key: leave empty if `API_KEY` is not set, otherwise use the same value
- Model: `Qwopus-GLM-18B-Healed-Q4_K_M`

## Long Context Guidance

- Start with `CTX_SIZE=65536`
- If VRAM is tight, lower `CTX_SIZE` first
- If startup still fails, lower `GPU_LAYERS`
- For slower but more memory-efficient runs, keep `CACHE_TYPE_K=q8_0` and
  `CACHE_TYPE_V=q8_0`

## Troubleshooting

- Port already in use:
  - change `PORT` in `.env`
  - or stop the service using the same port
- CUDA build failure:
  - confirm `nvidia-smi` works on the host
  - confirm Docker can use the NVIDIA runtime
  - confirm the CUDA architecture is correct for your GPU
- Model path error:
  - confirm `MODEL_PATH` points to an existing file under `./models`
- Context too large:
  - lower `CTX_SIZE`
  - lower `BATCH_SIZE` and `UBATCH_SIZE`
  - if needed, lower `GPU_LAYERS`

## Runtime Markers

In compose mode, `run/llama-server.pid` and `run/llama-server.container_id`
store the container id for the active server. They are used by the stop and
health-check scripts.
