# 模型 Profile 路线

本文记录部署 profile 的证据口径。当前 profile 清单、含义和实测吞吐统一维护在
[Profile 导引](../profiles/README.zh-CN.md)。

`Profile` 是 `launcher.sh` 选择的相对 `.env` 路径；具体 checkpoint 仍然通过
`MODEL_DIR` 单独选择。

目标 profile 和未完成路线追踪见
[Profile 蓝图草案](profile-blueprint.zh-CN.md)。

## 证据口径

完整通过表示真实大 prompt 请求返回 HTTP 200、stream 正常结束，并且至少生成
1 个 completion token。

平台期通过表示真实大 prompt 进入 prefill，显存达到稳定平台，后端持续处理高
上下文 chunk，并且在主动停止测试前没有 OOM 或空 stream。

只 load 成功、READY、health 通过、小窗口 smoke、空 stream，都不算容量证据。

## KV 精度定位

- FP16/default KV 是质量路线。
- INT8 KV 是质量 / 容量平衡路线。
- TQ4NC 是压缩路线。
- TQK8V4 目前没有证明相对 INT8 KV 有实用优势，不作为正式路线。

## 说明

- Profile 按 `profiles/<model>/<mode>/<weight>/<route>.env` 组织。
- 模式目录是预设的一部分，因为 safe 和 fast 的图执行策略、显存压力不同。
  safe 模式允许 FP16/default KV 使用 MTP；量化 KV 在 safe 模式下必须关闭
  MTP。normal 是中间诊断档，只用于兼容 profile 的手动对比。
- Gemma 保留为第二路线。FP16/default KV 的 MTP 和快速 prefill 路线都有
  benchmark 证据，但还没有 Gemma 预设晋升为生产路线。当前 noMTP FP16 路线
  可以跑 64K，但速度慢且输出重复；INT8 KV 和 TurboQuant 256K 路线不晋升。
- `two256K` 已测试但不采用：可以 admission 两个请求，但 INT8-KV prefill
  workspace 分配时 OOM，并返回空 stream。正式双工作区路线提升为 `two250K`。
- TurboQuant YaRN 也测试过 448K 和 440K。两者都在约 449,280-token 估算边界
  附近 admission 失败；400K 虽然完整通过，但容量和质量都不如 INT8 KV YaRN
  512K，因此不作为预设 profile。
- 吞吐背景记录见
  [Qwen3.6 KV 吞吐 Sweep](qwen36-kv-throughput-sweep.zh-CN.md) 和
  [MTP 任务敏感性](mtp-task-sensitivity.md)。
