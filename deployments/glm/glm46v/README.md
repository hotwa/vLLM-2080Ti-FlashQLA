# GLM-4.6V 本地推理服务栈

使用 vLLM 部署 GLM-4.6V-NVFP4 模型，通过 LiteLLM 直接提供 Anthropic API 兼容接口。

## 架构概览

```
┌─────────────────────────────────────────────────────────────────┐
│                         服务架构                                 │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│  ┌──────────────┐                                               │
│  │  Claude Code │                                               │
│  │    Cursor    │     ┌─────────────┐     ┌─────────────────┐  │
│  │    Kiro      │────▶│   LiteLLM   │────▶│      vLLM       │  │
│  │    ...       │     │    :4000    │     │  GLM-4.6V-NVFP4  │  │
│  └──────────────┘     │             │     │ (容器内网 :8000) │  │
│                       │  Anthropic  │     └──────────────────┘  │
│                       │  兼容层     │                          │
│                       │  路由/别名  │     ┌─────────────────┐  │
│                       │  负载均衡   │────▶│  其他推理后端   │  │
│                       └─────────────┘     │  Ollama/TGI/... │  │
│                                           └─────────────────┘  │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

## 组件说明

| 组件 | 端口 | 功能 |
|------|------|------|
| LiteLLM | 4000 | Anthropic API 兼容、路由、模型别名、负载均衡 |
| vLLM | 8000 | GLM-4.6V-NVFP4 模型推理 (仅容器内部访问) |
| Tailscale GW | - | (仅 Tailscale 模式) 远程访问网关 |

## 硬件要求

- NVIDIA GPU，64GB+ VRAM（测试于 RTX PRO 6000 96GB）
- Docker with NVIDIA runtime
- WSL2 (Windows) 或原生 Linux

## 快速开始

### 1. 下载模型

```bash
pip install huggingface_hub
huggingface-cli download GadflyII/GLM-4.6V-NVFP4 \
  --local-dir ~/.cache/huggingface/hub/models--GadflyII--GLM-4.6V-NVFP4
```

> **注意：** NVFP4 模型不需要手动修复配置文件，模型仓库已包含完整的 processor 配置。

### 2. 修复缺失的配置文件

> **NVFP4 版本不需要此步骤。** 模型仓库已包含完整的 `preprocessor_config.json`。

```bash
# 以下步骤仅适用于 AWQ 量化版本（已废弃）
MODEL_DIR=$(find ~/.cache/huggingface/hub/models--cyankiwi--GLM-4.6V-AWQ-4bit/snapshots -maxdepth 1 -type d | tail -1)
cp preprocessor_config.json "$MODEL_DIR/"
```

### 3. 配置环境变量

```bash
cp .env.example .env
# 编辑 .env 设置必要变量 (如 HF_TOKEN)
```

### 4. 启动服务

**选项 A: 本地部署 (默认)**

适用于本地开发，暴露 LiteLLM 端口 (4000)，vLLM 仅在容器内网运行。

```bash
docker compose up -d
docker logs -f glm-4.6v-nvfp4
```

**选项 B: Tailscale 远程访问**

适用于远程服务器，通过 Tailscale 内网访问，不暴露公网端口。

```bash
# 确保 .env 中配置了 TS_AUTHKEY
docker compose -f docker-compose-tailscale.yml up -d
docker logs -f glm-4.6v-nvfp4
```

## 客户端配置

### Claude Code / Cursor / Kiro

LiteLLM 原生支持 Anthropic API 协议，直接连接即可：

```bash
export ANTHROPIC_BASE_URL=http://your-server:4000
export ANTHROPIC_API_KEY=sk-your-litellm-master-key
```

### 直接使用 OpenAI 兼容 API

```bash
curl http://localhost:4000/v1/chat/completions \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer sk-your-litellm-master-key" \
  -d '{
    "model": "claude-3-5-sonnet",
    "messages": [{"role": "user", "content": "Hello!"}],
    "max_tokens": 512
  }'
```

## 模型别名配置

在 `litellm-config.yaml` 中配置模型映射：

```yaml
model_list:
  - model_name: claude-3-5-sonnet      # 客户端请求的名称
    litellm_params:
      model: openai/GadflyII/GLM-4.6V-NVFP4
      api_base: http://localhost:8000/v1
      api_key: anything
      drop_params: true

  - model_name: claude-haiku-4-5-20251001
    litellm_params:
      model: openai/qwen3-code-flash
      api_base: http://100.64.0.4:8080/v1  # 其他推理后端
      api_key: anything
      drop_params: true
```

## 为什么移除 anthropic-proxy？

LiteLLM 已原生支持：
- Anthropic streaming 协议
- Tool calling 循环
- 连接重试和 keep-alive
- 避免 EPIPE 错误

直接使用 LiteLLM 作为 Anthropic 兼容层更稳定，减少一层代理。

## 已知问题

| 问题 | 解决方案 |
|------|----------|
| Context Window 超限 (131072 tokens) | 清理对话上下文，开新会话 |
| `Expected ProcessorMixin` 错误 | Dockerfile 已升级 transformers 到 5.0.0rc0 |
| 缺少 `preprocessor_config.json` | (仅旧版AWQ需) 复制本目录下的文件到模型目录 |
| LiteLLM 报 `POST /v1/messages?beta=true` 400 + `ProxyException` | 确认请求携带 `x-api-key`/`Authorization`，并与 `.env.litellm` 的 `LITELLM_MASTER_KEY` 一致；Claude Code 请将 `ANTHROPIC_API_KEY` 设置为该 key |

## 停止服务

```bash
# 本地模式
docker compose down

# Tailscale 模式
docker compose -f docker-compose-tailscale.yml down
```

## 相关文档

- [LiteLLM 文档](https://docs.litellm.ai/)
- [vLLM 文档](https://docs.vllm.ai/)
