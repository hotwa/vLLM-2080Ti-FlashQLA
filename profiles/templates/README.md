# Chat Template Presets

These templates are optional launcher presets. Select them from
`launcher.sh` -> `Profile` -> `Chat template preset`.

Route profiles do not store chat-template paths. A template, reasoning default,
default thinking budget, and tool-calling defaults are global service settings
so the same FP8/INT4/KV route can be reused with different prompt rendering
behavior.

## Presets

- `qwen-froggeric-v20.jinja`: Qwen 3.5/3.6 fixed chat template from
  <https://huggingface.co/froggeric/Qwen-Fixed-Chat-Templates>. Useful when you
  want its tool/reasoning/KV-cache-safe rendering behavior.

Use `model default` in the launcher to avoid passing `--chat-template`.
