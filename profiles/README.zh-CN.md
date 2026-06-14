# Profile 导引

语言：[English](README.md) | 简体中文

这里是 vLLM 2080Ti Definitive 自带的启动 profile。一个 profile 只是运行参数
的 `.env` 预设，不包含模型权重路径；权重目录通过 `launcher.sh` 或
`MODEL_DIR=...` 单独选择。

目录结构：

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

模式目录是预设的一部分，因为 safe 和 fast 的图执行策略、显存压力不同。

`profiles/templates/` 存放可选 chat template 预设。它们通过 launcher 作为全局
服务设置选择；具体 route profile 不保存 chat template、GPU、端口、reasoning
默认值或工具调用默认值。

文件名描述路线：

```text
<kv-precision>-<context>-<mtp>-<message-type>.env
```

KV 精度定位：

- `fp16kv`：质量路线。
- `int8kv`：质量 / 容量平衡路线。

启动模式由用户显式选择，或使用 launcher 默认值。profile 只声明
`COMPATIBLE_MODES`；launcher 会根据这个列表对所选模式做二次校验。

- `safe`：默认生产模式。FP16/default KV 可以使用 MTP；量化 KV 必须关闭 MTP。
- `fast`：高性能模式。允许量化 KV + MTP，但显存和质量风险更高。

下面吞吐统一使用一个合成 benchmark 口径：`/v1/completions`、纯 `" the"`
填充、`PP4096/TG128`、`ignore_eos=true`、`return_token_ids=true`、1 次
warmup + 3 次 measured，并取 measured median。格式为 `prefill tok/s /
decode tok/s`。

`fast` 表里的数字都来自 launcher `MODE=fast`。FP16/default KV + MTP 在必要
时会走图安全回退；量化 KV + MTP 只有在正确性通过时才使用更快的图路径。

## 已验证 Profile

### Qwen3.6 27B Safe

| Profile | 含义 | 兼容模式 | 上下文 | KV | MTP | 消息 | 并发 | PP4096/TG128 |
|---|---|---|---:|---|---:|---|---:|---:|
| `qwen27b/safe/fp8/fp16kv-128K-mtp3-text-only.env` | FP8 权重质量纯文本路线。 | safe | 128K | FP16/default | 3 | text-only | 1 | 1610.39 / 76.34 |
| `qwen27b/safe/fp8/fp16kv-80K-mtp3-text-image.env` | FP8 质量图文路线；图像 profiling 会降低可用上下文。 | safe | 80K | FP16/default | 3 | text+image | 1 | 1614.53 / 75.68 |
| `qwen27b/safe/fp8/int8kv-256K-nomtp-text-only.env` | FP8 长文本稳定路线；关闭 MTP，换取量化 KV 下更稳输出。 | safe | 256K | INT8 | 0 | text-only | 1 | 1654.07 / 32.44 |
| `qwen27b/safe/int4/fp16kv-256K-mtp3-text-only.env` | INT4 权重质量纯文本路线，当前主力 256K profile。 | safe | 256K | FP16/default | 3 | text-only | 1 | 1738.75 / 85.66 |
| `qwen27b/safe/int4/fp16kv-240K-mtp3-text-image.env` | INT4 + FP16/default KV 质量图文路线。 | safe | 240K | FP16/default | 3 | text+image | 1 | 1742.93 / 80.33 |

### Qwen3.6 27B Fast

| Profile | 含义 | 兼容模式 | 上下文 | KV | MTP | 消息 | 并发 | PP4096/TG128 |
|---|---|---|---:|---|---:|---|---:|---:|
| `qwen27b/fast/fp8/int8kv-256K-mtp3-text-only.env` | FP8 长文本速度路线；量化 KV + MTP3。 | fast | 256K | INT8 | 3 | text-only | 1 | 1602.47 / 74.93 |
| `qwen27b/fast/fp8/fp16kv-96K-mtp3-text-only.env` | FP8 + FP16/default KV fast 纯文本回退路线。 | fast | 96K | FP16/default | 3 | text-only | 1 | 1598.44 / 79.56 |
| `qwen27b/fast/int4/fp16kv-250K-mtp3-text-only.env` | INT4 + FP16/default KV fast 纯文本路线。 | fast | 250K | FP16/default | 3 | text-only | 1 | 1725.88 / 86.44 |
| `qwen27b/fast/int4/int8kv-256K-mtp3-text-only.env` | INT4 + INT8 KV 平衡长文本 fast 路线。 | fast | 256K | INT8 | 3 | text-only | 1 | 1727.13 / 96.93 |
| `qwen27b/fast/int4/int8kv-two250K-mtp3-text-only.env` | 双工作区隔离路线，不用于追求并行长 prefill 吞吐。 | fast | 每工作区 250K | INT8 | 3 | text-only | 2 | 1735.51 / 91.63 |
| `qwen27b/fast/int4/int8kv-512K-yarn-mtp3-text-only.env` | YaRN 超长单请求文本路线。 | fast | 512K | INT8 + YaRN | 3 | text-only | 1 | 1741.32 / 95.41 |
