# rico03 Qwen3.6 Opus GGUF Download and Smoke

## Downloaded Models

| Model | Path | Size | Sha256 |
|---|---|---:|---|
| `Qwen3.6-35B-A3B-Opus-Q4_K_S.gguf` | `models/gguf/Qwen3.6-35B-A3B-Opus-Q4_K_S.gguf` | `19889903360` bytes | `ed3250ebaf69e821652e50e6b0c2f7714bf203eae0e5072447464ae2b905aeaa` |
| `Qwen3.6-35B-A3B-Opus-Q5_K_M.gguf` | `models/gguf/Qwen3.6-35B-A3B-Opus-Q5_K_M.gguf` | `24729131776` bytes | `28165dd0e3e851f88a85db1c880afe8ba615508952fc5576ca9cfa8ce2cd777a` |

## Smoke Results

Both models were started with `ik_llama.cpp` on the dual RTX 2080 Ti 22GB machine using:

- `MAX_MODEL_LEN=131072`
- `REASONING_BUDGET=0`
- `CHAT_TEMPLATE_ENABLE_THINKING=0`
- Qwen3.6 official chat template

### Q4_K_S

- `/v1/models` responded with HTTP 200
- Chinese prompt: `用一句话解释为什么天空是蓝色的。`
- Output was coherent Chinese and included a visible `<|think|>` section
- Result: `passed`

### Q5_K_M

- `/v1/models` responded with HTTP 200
- Chinese prompt: `用一句话解释为什么天空是蓝色的。`
- Output was coherent Chinese and returned a direct answer in Chinese
- Result: `passed`

## Notes

- The `Q4_K_S` and `Q5_K_M` files in this repo could not be fetched through `hf_hub_download` directly, but both were downloaded successfully via Hugging Face git/LFS.
- `Q5_K_M` is the better default if you care more about answer quality and fewer prompt artifacts.
- `Q4_K_S` is the better fallback if you want a smaller model footprint.
