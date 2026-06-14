以下是对 vLLM在不同后端下 MLA（Multi-Head Latent Attention）报错原因的去重总结及解决方案：

1.  **TORCH_SDPA**: 非 PyTorch 算子能力不足，而是 vLLM v1 架构中 **attention registry（注册表）缺失或枚举未包含**该路径，导致直接抛出 `ValueError`。
2.  **TRITON_MLA**: 在 Prefill 阶段会调用 FlashAttention，其 **算力要求为 cc >= 8.0**。由于当前设备为 SM75 (cc 7.5)，触发布局限制导致崩溃。
3.  **FLASHINFER_MLA**: 受 **双重限制**：
    *   算力 cc 限制；
    *   **形状不匹配**：当前 `qk_nope_head_dim=192`，而该算子主要适配 DeepSeek 的 128/64/512 规格。
4.  **CUTLASS_MLA**: vLLM 代码中 **硬编码屏蔽了 cc 7.5 设备**，直接判定不支持，与 shape 无关。

**解决方案：**
设置环境变量（如 `VLLM_MLA_DISABLE=1`），强制 vLLM 走 **非 MLA** 的通用 Attention 实现（如 Paged Attention / SDPA / xformers 等），以兼容 SM75 架构和当前模型维度。