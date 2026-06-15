# [已弃用] Anthropic Proxy

> ⚠️ **此组件已弃用**，LiteLLM 原生支持 Anthropic API 协议，无需额外代理层。

## 新架构

```
Claude Code / Cursor / Kiro
         ↓
    LiteLLM :4000  (Anthropic API 兼容)
         ↓
    vLLM / 其他推理后端
```

## 客户端配置

直接连接 LiteLLM：

```bash
export ANTHROPIC_BASE_URL=http://your-server:4000
export ANTHROPIC_API_KEY=dummy
```

## 为什么移除？

LiteLLM 已原生支持：
- Anthropic streaming 协议
- Tool calling 循环
- 连接重试和 keep-alive
- 避免 EPIPE 错误

减少一层代理，架构更简单，稳定性更好。

## 相关文档

- [LiteLLM Anthropic 支持](https://docs.litellm.ai/docs/providers/anthropic)
