# AGENTS.md

This project is a self-contained local deployment for `ik_llama.cpp` on two
RTX 2080 Ti 22GB cards with NVLink.

Current local GGUFs in `models/gguf`:

- `Qwen3.6-35B-A3B-Opus-Q5_K_M.gguf`
- `Qwen3.6-35B-A3B-Opus-Q4_K_S.gguf`
- `Qwen3.6-35B-A3B-UD-Q5_K_M.gguf`

The Opus files were downloaded from `rico03/Qwen3.6-35B-Opus-Reasoning-GGUF`,
not uploaded from this workspace.

Current default runtime:

- Model: `Qwen3.6-35B-A3B-Opus-Q5_K_M.gguf`
- Template mode: `JINJA=0` meaning "use the GGUF metadata template"
- Endpoint: OpenAI-compatible `http://127.0.0.1:8000/v1`

Operational rules:

- Do not print or commit Hugging Face tokens.
- Prefer runtime environment variables or the local ignored `.env`.
- Keep downloads, build artifacts, logs, and model weights outside version control.
- Update the files in `results/` after each major stage.
- Use `scripts/setup_env.sh` before downloading or building.
- Use `scripts/download_model.sh` for model acquisition and integrity checks.
- Use `scripts/fetch_ik_llama.sh` before building if `third_party/ik_llama.cpp` is missing.
- When launching the current setup, set `MODEL_FILE=Qwen3.6-35B-A3B-Opus-Q5_K_M.gguf`;
  use `Qwen3.6-35B-A3B-Opus-Q4_K_S.gguf` when you want the smaller fallback.
- Prefer the GGUF metadata template by default (`JINJA=0`).
- Use the external `jinja/qwopus_v3_template.jinja` only when explicitly testing
  OpenCode/OpenClaw template behavior.
- Keep the primary validation gate at `131072` tokens.
- Benchmark at `16384`, `32768`, and `65536` tokens with a deterministic prompt corpus.

Suggested workflow:

1. Detect token availability.
2. Download the GGUF.
3. Fetch and build `ik_llama.cpp`.
4. Start the server and validate `/v1/models`.
5. Run a smoke chat completion.
6. Run the 16k / 32k / 64k benchmark sweep.
7. If tool calls loop, inspect the client/plugin layer before changing the model.
