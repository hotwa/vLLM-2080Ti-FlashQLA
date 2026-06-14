# Profile 验证蓝图与结果

本文追踪目标 profile、回退测试和当前结论。正式使用入口以
[Profile 导引](../profiles/README.zh-CN.md) 为准。

状态：✅ 已通过；🟡 已验证但不晋升；🔴 已失败；🧪 仅实验入口。

## 证据口径

- 完整通过：真实大 prompt 请求返回 HTTP 200、stream 正常结束，并生成至少
  1 个 completion token。
- 平台期通过：真实大 prompt 进入 prefill，显存达到稳定平台，后端持续处理高
  上下文 chunk，并且主动停止前没有 OOM 或空 stream。
- 吞吐统一口径：`/v1/completions`、纯 `" the"` 填充、`PP4096/TG128`、
  `ignore_eos=true`、`return_token_ids=true`、1 次 warmup + 3 次 measured，
  取 measured median。
- 不采纳：只 load 成功、READY、health 通过、小窗口 smoke、空 stream。

## Qwen3.6 27B 已通过 Profile

| Profile | 状态 | 关键参数 | PP4096/TG128 | 容量 / 正确性证据 |
|---|---|---|---:|---|
| `qwen27b/safe/fp8/fp16kv-128K-mtp3-text-only.env` | ✅ | FP8；safe；FP16 KV；128K；MTP3 | 1610.39 / 76.34 | `130000` prompt + 8 gen 完整通过。 |
| `qwen27b/safe/fp8/fp16kv-80K-mtp3-text-image.env` | ✅ | FP8；safe；FP16 KV；80K；MTP3；图文 | 1614.53 / 75.68 | `80000` prompt + 1 图 + 64 gen 完整通过，图像识别正确。 |
| `qwen27b/safe/fp8/int8kv-256K-nomtp-text-only.env` | ✅ | FP8；safe；INT8 KV；256K；noMTP | 1654.07 / 32.44 | `260000` prompt + 8 gen 完整通过。 |
| `qwen27b/safe/int4/fp16kv-256K-mtp3-text-only.env` | ✅ | INT4；safe；FP16 KV；256K；MTP3 | 1738.75 / 85.66 | 原生 256K 真实大 prompt 通过。 |
| `qwen27b/safe/int4/fp16kv-240K-mtp3-text-image.env` | ✅ | INT4；safe；FP16 KV；240K；MTP3；图文 | 1742.93 / 80.33 | `240000` 文本 tokens + 1 图 + 64 gen 完整通过，图像识别正确。 |
| `qwen27b/fast/fp8/int8kv-256K-mtp3-text-only.env` | ✅ | FP8；fast；INT8 KV；256K；MTP3 | 1602.47 / 74.93 | `261120` prompt 进入稳定显存平台期。 |
| `qwen27b/fast/fp8/fp16kv-96K-mtp3-text-only.env` | ✅ | FP8；fast；FP16 KV；96K；MTP3；纯文本 | 1598.44 / 79.56 | `96000` prompt + 8 gen 完整通过。 |
| `qwen27b/fast/int4/fp16kv-250K-mtp3-text-only.env` | ✅ | INT4；fast；FP16 KV；250K；MTP3；纯文本 | 1725.88 / 86.44 | `250000` prompt + 8 gen 完整通过；LongGen3 混合任务优于 MTP5。 |
| `qwen27b/fast/int4/int8kv-256K-mtp3-text-only.env` | ✅ | INT4；fast；INT8 KV；256K；MTP3；纯文本 | 1727.13 / 96.93 | `261120` prompt 进入稳定显存平台期。 |
| `qwen27b/fast/int4/int8kv-two250K-mtp3-text-only.env` | ✅ | INT4；fast；INT8 KV；双工作区；MTP3；纯文本 | 1735.51 / 91.63 | 两个并发 `254976` prompt 请求进入稳定显存平台期。 |
| `qwen27b/fast/int4/int8kv-512K-yarn-mtp3-text-only.env` | ✅ | INT4；fast；INT8 KV；512K YaRN；MTP3 | 1741.32 / 95.41 | `520000` prompt 进入稳定平台期；容量边界极窄。 |

## Qwen3.6 27B 容量通过但不晋升 Profile

这些条目有容量 / 速度证据，但图像正确性失败，不作为图文推荐路线。已经通过的
profile 不需要重测。

| Profile | 状态 | 目标 | 当前结论 |
|---|---|---|---|
| `qwen27b/fast/fp8/fp16kv-76K-mtp3-text-image.env` | 🟡 | FP8；fast；FP16 KV；76K；MTP3；图文 | 容量和速度通过；`76000` prompt + 1 图 + 64 gen 完整返回；PP4096/TG128 为 1601.55 / 49.93；测试图识别失败，不晋升。 |
| `qwen27b/fast/int4/fp16kv-232K-mtp3-text-image.env` | 🟡 | INT4；fast；FP16 KV；232K；MTP3；图文 | 容量和速度通过；`232000` prompt + 1 图完整返回；PP4096/TG128 为 1703.21 / 60.02；测试图识别失败，不晋升。 |
| `qwen27b/fast/int4/int8kv-256K-mtp3-text-image.env` | 🟡 | INT4；fast；INT8 KV；256K；MTP3；图文 | 容量和合成速度通过，PP4096/TG128 为 1727.82 / 94.49；测试图正确性失败，不晋升。 |

## 实验 / 失败路线

| Profile / candidate | 状态 | 实测结果 | 结论 |
|---|---|---|---|
| `qwen27b/experimental/fp8/int8kv-232K-nomtp-text-image.env` | 🔴 | 232K 可启动，合成速度 1653.82 / 32.43；图像识别失败。 | 不晋升。 |
| `qwen27b/experimental/fp8/int8kv-216K-mtp3-text-image.env` | 🔴 | 216K 可启动，合成速度 1605.97 / 73.78；输出重复/错误。 | 不晋升。 |
| `qwen27b/experimental/fp8/tqk8v4-256K-mtp3-text-only.env` | 🧪 | 当前 exact 256K profile 在 CUDA graph memory profiling 下 admission 失败，估算最大 `247,104` tokens；早期单次短测不再作为 profile 吞吐证据。 | 仅调试入口，无容量证据。 |
| INT4 + TQ4NC + YaRN | 🟡 | 400K 完整通过，1692.90 / 89.67；448K/440K admission 失败。 | 容量和质量定位不如 INT8 KV YaRN 512K，不做预设。 |
| `two256K` | 🔴 | admission 后 INT8-KV prefill workspace OOM，并返回空 stream。 | 改用 two250K。 |
| INT4 + FP16/default KV + MTP5 LongGen3 | 🟡 | 同一 fast 路线下，MTP5 aggregate decode after TTFT 为 61.49，低于 MTP3 的 64.41；代码题更快，但技术分析和文学题更慢。 | 不作为混合任务默认 profile。 |

## Gemma4 31B 实验结果

| Profile | 状态 | 实测结果 | 结论 |
|---|---|---|---|
| `gemma31b/experimental/int4/fp16kv-64K-nomtp-text-only.env` | 🧪 | 该 profile 是 noMTP 路线；noMTP 64K 完整通过。uncached 合成首轮 586.64 / 26.99；重复 measured prefill 命中 prefix cache，不作可比吞吐。长输出质量测试有明显重复。 | 仅实验。 |
| `gemma31b/experimental/int4/int8kv-256K-nomtp-text-only.env` | 🔴 | 原 profile KV page-size 初始化失败；关闭 hybrid KV 后 FlashInfer 报 `Unsupported max_mma_kv: 0`；慢速 fallback 估算最大约 47K。 | 不晋升。 |
| `gemma31b/experimental/int4/tq4nc-256K-nomtp-text-only.env` | 🔴 | 256K admission 失败；估算最大约 59,632 tokens。 | 不晋升。 |
