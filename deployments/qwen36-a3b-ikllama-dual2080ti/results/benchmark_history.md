# Benchmark History

Qwen3.6-35B-A3B-UD-Q4_K_M on dual RTX 2080 Ti 22GB + NVLink, using
`ik_llama.cpp`.

## Measured points

| Context | Prompt tokens | Completion tokens | TTFT (s) | Prompt proc tok/s | Decode tok/s | Peak VRAM (MiB) | Status |
|---:|---:|---:|---:|---:|---:|---:|---|
| 16,384 | 12,163 | 256 | 4.525 | 2,688.03 | 69.05 | 12,387 | ok |
| 32,768 | 25,259 | 256 | 10.729 | 2,354.20 | 65.89 | 12,399 | ok |
| 65,536 | 51,549 | 256 | 29.904 | 1,723.79 | 54.19 | 12,425 | ok |
| 131,072 | 104,263 | 30 | 117.881 | 884.479 | 37.133 | 12,301 | ok |
| 262,144 | 209,309 | 30 | 412.872 | 506.959 | 19.318 | 12,951 | ok |

## Decay vs 16k baseline

| Context | Prompt proc ratio | Decode ratio | TTFT multiplier |
|---:|---:|---:|---:|
| 32,768 | 0.876 | 0.954 | 2.371 |
| 65,536 | 0.641 | 0.785 | 6.608 |
| 131,072 | 0.329 | 0.538 | 26.052 |
| 262,144 | 0.189 | 0.280 | 91.245 |

## Interpretation

- `131,072` is the first long-context point that clears the practical
  `30 tok/s` decode threshold on this machine.
- `262,144` does not meet that target; decode falls to about `19.3 tok/s`.
- `128k` is therefore the recommended default if you want a long-running
  OpenAI-compatible API on this hardware.
