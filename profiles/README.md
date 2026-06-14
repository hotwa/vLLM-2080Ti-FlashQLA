# Profile Guide

Language: English | [简体中文](README.zh-CN.md)

This directory contains launch profiles for vLLM 2080Ti Definitive. A profile
is an `.env` preset for runtime parameters only; it does not include the
checkpoint path. Choose the model directory separately in `launcher.sh` or with
`MODEL_DIR=...`.

Profile layout:

```text
profiles/
  templates/
  qwen27b/
    safe/
      fp8/
      int4/
    fast/
      fp8/
      int4/
```

The mode directory is part of the preset because safe and fast profiles have
different graph behavior and VRAM pressure.

`profiles/templates/` contains optional chat-template presets. They are selected
from the launcher as a global service setting; route profiles do not store chat
templates, GPU devices, ports, reasoning defaults, or tool-calling defaults.

File names describe the intended route:

```text
<kv-precision>-<context>-<mtp>-<message-type>.env
```

KV positioning:

- `fp16kv`: quality route.
- `int8kv`: quality / capacity balance.

Launch mode is selected by the user or by the launcher default. Profiles declare
`COMPATIBLE_MODES`; the launcher validates the selected mode against that list.

- `safe`: production default. FP16/default KV may use MTP; quantized KV must
  use noMTP.
- `fast`: high-performance mode. Quantized KV + MTP is allowed, with higher
  memory and quality risk.

Throughput below uses one synthetic benchmark口径: `/v1/completions`, pure
`" the"` filler, `PP4096/TG128`, `ignore_eos=true`,
`return_token_ids=true`, 1 warmup + 3 measured runs, measured median. Values
are reported as `prefill tok/s / decode tok/s`.

The `fast` rows are measured with launcher `MODE=fast`. FP16/default KV + MTP
uses the graph-safe fallback when required; quantized KV + MTP may use the
faster graph path when it passes correctness checks.

## Validated Profiles

### Qwen3.6 27B Safe

| Profile | Meaning | Compatible modes | Context | KV | MTP | Messages | Seqs | PP4096/TG128 |
|---|---|---|---:|---|---:|---|---:|---:|
| `qwen27b/safe/fp8/fp16kv-128K-mtp3-text-only.env` | FP8 quality text route. | safe | 128K | FP16/default | 3 | text-only | 1 | 1610.39 / 76.34 |
| `qwen27b/safe/fp8/fp16kv-80K-mtp3-text-image.env` | FP8 quality image route. Image profiling reduces practical context. | safe | 80K | FP16/default | 3 | text+image | 1 | 1614.53 / 75.68 |
| `qwen27b/safe/fp8/int8kv-256K-nomtp-text-only.env` | FP8 safe long-text route. MTP is disabled for quantized-KV output stability. | safe | 256K | INT8 | 0 | text-only | 1 | 1654.07 / 32.44 |
| `qwen27b/safe/int4/fp16kv-256K-mtp3-text-only.env` | INT4 quality text route and main 256K profile. | safe | 256K | FP16/default | 3 | text-only | 1 | 1738.75 / 85.66 |
| `qwen27b/safe/int4/fp16kv-240K-mtp3-text-image.env` | INT4 + FP16/default KV quality image route. | safe | 240K | FP16/default | 3 | text+image | 1 | 1742.93 / 80.33 |

### Qwen3.6 27B Fast

| Profile | Meaning | Compatible modes | Context | KV | MTP | Messages | Seqs | PP4096/TG128 |
|---|---|---|---:|---|---:|---|---:|---:|
| `qwen27b/fast/fp8/int8kv-256K-mtp3-text-only.env` | FP8 long-text fast route with quantized KV + MTP3. | fast | 256K | INT8 | 3 | text-only | 1 | 1602.47 / 74.93 |
| `qwen27b/fast/fp8/fp16kv-96K-mtp3-text-only.env` | FP8 + FP16/default KV fast text fallback. | fast | 96K | FP16/default | 3 | text-only | 1 | 1598.44 / 79.56 |
| `qwen27b/fast/int4/fp16kv-250K-mtp3-text-only.env` | INT4 + FP16/default KV fast text route. | fast | 250K | FP16/default | 3 | text-only | 1 | 1725.88 / 86.44 |
| `qwen27b/fast/int4/int8kv-256K-mtp3-text-only.env` | INT4 + INT8 KV balanced long-text fast route. | fast | 256K | INT8 | 3 | text-only | 1 | 1727.13 / 96.93 |
| `qwen27b/fast/int4/int8kv-two250K-mtp3-text-only.env` | Two-workspace isolation route. This is not parallel long-prefill throughput. | fast | 250K per workspace | INT8 | 3 | text-only | 2 | 1735.51 / 91.63 |
| `qwen27b/fast/int4/int8kv-512K-yarn-mtp3-text-only.env` | YaRN ultra-long single-request text route. | fast | 512K | INT8 + YaRN | 3 | text-only | 1 | 1741.32 / 95.41 |
