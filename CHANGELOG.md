# Changelog

This changelog tracks the fork release version for vLLM 2080 Ti Definitive
Edition. It is separate from the upstream vLLM package version.

## v0.1.6 - 2026-06-09

- Adds explicit W8A8 checkpoint support documentation for the Quark INT8 route,
  including the tested `nameistoken/Qwen3.6-27B-Quark-W8A8-INT8` checkpoint.
- Updates the launcher display to separate the real vLLM `--quantization`
  value from the display-only W/A type (`W4A16`, `W8A16`, `W8A8`).
- Adds launcher service-status cache reporting for running services. Live
  `used` values and 30-second refresh are shown only when vLLM exposes real
  cache-usage metrics; otherwise the launcher reports total cache capacity only.
- Improves launcher startup preflight for large single-file checkpoints and
  cleans up residual vLLM processes after failed launches.
- Fixes launcher stop handling so orphaned vLLM API servers, worker processes,
  and resource trackers are discovered and cleaned up instead of leaving VRAM
  occupied.

## v0.1.5 - 2026-06-08

- Renames the public service manager to `launcher.sh` and keeps `build.sh` as
  the one-click source build entry point.
- Updates launcher modes to `safe`, `normal`, and `fast`, with route profiles
  split by model, mode, and weight precision.
- Adds chat template presets and service-level thinking budget defaults while
  keeping global runtime controls out of route profile files.
- Refreshes the Qwen3.6 profile documentation and restores the KV throughput
  sweep SVG charts.

## v0.1.4 - 2026-06-06

- Slims the public repository down to the focused SM75 runtime source tree,
  launcher scripts, validated profiles, and project documentation.
- Keeps Docker artifacts out of this source release; Docker packaging remains a
  separate future deployment layer.
- Adds the interactive `launcher.sh` service manager and one-click `build.sh`
  source build entry point.
- Uses the public launcher modes `safe`, `normal`, and `fast`, with validated
  profiles organized under model-specific profile directories.
- Carries forward the `v0.1.3` graph-safety runtime fixes while removing
  upstream CI/docs/test bulk from the public source tree.

## v0.1.3 - 2026-06-05

- Adds the issue #24 MTP graph-safety fix for hybrid Mamba/GDN models.
- Makes production profiles safer by default: Native MTP + hybrid recurrent KV
  layers fall back from full decode CUDA Graph replay to PIECEWISE/NONE.
- Keeps the old peak-throughput route available for explicit speed benchmarking
  via `VLLM_ALLOW_MAMBA_SPEC_FULL_CUDAGRAPH=1`.

## v0.1.2 - 2026-06-04

- Public stable snapshot for the SM75 TP=2 CUDA 12.8 runtime.
- Keeps the upstream vLLM base at `0.21.0` while versioning this fork as an
  independent 2080 Ti runtime distribution.
- Updates the documented Qwen3.6 and Gemma4 runtime routes, tested checkpoint
  list, launcher profile guidance, and benchmark evidence links.

## v0.1.1

- Follow-up compatibility fixes for editable/source builds and optional CUDA
  extension imports on SM75 environments.

## v0.1.0

- Initial public stable snapshot of the dual 2080 Ti / SM75 TP=2 runtime.
