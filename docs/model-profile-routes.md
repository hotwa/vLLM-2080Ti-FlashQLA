# Model Profile Routes

This document records the evidence rules behind the deployment profiles. The
current profile catalog, meanings, and measured throughput live in
[Profile Guide](../profiles/README.md).

`Profile` is the relative `.env` path selected by `launcher.sh`; the concrete
checkpoint is selected separately with `MODEL_DIR`.

## Evidence Rule

Full pass means a real large-prompt request returns HTTP 200, finishes the
stream, and generates at least one completion token.

Platform pass means a real large-prompt request enters prefill, GPU memory
reaches a stable plateau, the backend continues processing high-context chunks,
and no OOM or empty-stream failure appears before the test is intentionally
stopped.

Load-only, READY-only, health-only, small-window smoke, and empty-stream results
are not capacity evidence.

## KV Positioning

- FP16/default KV is the quality route.
- INT8 KV is the balanced quality/capacity route.
- TQ4NC is the compression route.
- TQK8V4 is not a formal route because current evidence does not show a
  practical advantage over INT8 KV.

## Notes

- Profiles are organized as `profiles/<model>/<mode>/<weight>/<route>.env`.
- The mode directory is part of the shipped preset because safe and fast
  profiles have different graph behavior and VRAM pressure. Safe mode allows
  FP16/default KV with MTP; quantized KV in safe mode must use noMTP. Normal is
  available as a middle diagnostic mode for compatible profiles.
- Gemma remains a second-line route. FP16/default-KV MTP and fast-prefill routes
  have benchmark evidence, but no Gemma preset is promoted as a production route
  yet. The currently validated noMTP FP16 route can run 64K but is
  slow/repetitive; INT8 KV and TurboQuant 256K routes are not promoted.
- `two256K` was tested but rejected: it admitted two requests, then OOMed during
  INT8-KV prefill workspace allocation and returned empty streams. The promoted
  two-workspace route is `two250K`.
- TurboQuant YaRN was validated at 400K, while 448K and 440K both failed
  admission near an estimated 449,280-token edge. It is not a preset profile
  because INT8 KV YaRN reaches 512K with better capacity and quality.
- Throughput background is kept in
  [Qwen3.6 KV Throughput Sweep](qwen36-kv-throughput-sweep.md) and
  [MTP Task Sensitivity](mtp-task-sensitivity.md).
