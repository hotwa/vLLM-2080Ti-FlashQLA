# Benchmark Summary

- Generated: 2026-04-19T15:49:41+08:00
- Profile: `long_context`
- Model: `Qwen3.6-35B-A3B-UD-Q4_K_M`

| Context | Prompt tokens | Completion tokens | TTFT (s) | Prompt proc tok/s | Decode tok/s | Peak VRAM (MiB) | Status |
|---:|---:|---:|---:|---:|---:|---:|---|
| 131072 | 104263 | 30 | 117.881 | 884.479 | 37.133 | 12301 | ok |

## Decay vs 16k baseline

| Context | Prompt proc ratio | Decode ratio | TTFT multiplier |
|---:|---:|---:|---:|
| 131072 | 1.000 | 1.000 | 1.000 |
