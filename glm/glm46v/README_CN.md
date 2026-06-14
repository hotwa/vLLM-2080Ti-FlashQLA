# GLM-4.6V-NVFP4 Docker 部署

使用 vLLM 在 Docker 中部署 GLM-4.6V-NVFP4 模型，充分利用 GPU 算力。

## 环境要求

- NVIDIA GPU，显存 64GB+（已在 RTX PRO 6000 96GB 上测试）
- Docker + NVIDIA runtime
- WSL2（Windows）或原生 Linux

## 快速开始

### 1. 下载模型权重

```bash
# 使用 huggingface-cli
pip install huggingface_hub
huggingface-cli download GadflyII/GLM-4.6V-NVFP4 --local-dir ~/.cache/huggingface/hub/models--GadflyII--GLM-4.6V-NVFP4
```

### 2. 修复缺失的 Processor 配置

> **NVFP4 版本不需要此步骤。** 模型仓库已包含完整的 `preprocessor_config.json`。

```bash
# 以下步骤仅适用于 AWQ 量化版本（已废弃）
MODEL_DIR=$(find ~/.cache/huggingface/hub/models--cyankiwi--GLM-4.6V-AWQ-4bit/snapshots -maxdepth 1 -type d | tail -1)
cp preprocessor_config.json "$MODEL_DIR/"
```

### 3. 构建并运行

**选项 A: 本地部署 (默认)**

适用于本地开发，暴露 LiteLLM 端口 (4000)，vLLM 仅在容器内网运行。

```bash
docker compose build
docker compose up -d
docker logs -f glm-4.6v-nvfp4
```

**选项 B: Tailscale 远程访问**

适用于远程服务器，通过 Tailscale 内网访问，不暴露公网端口。

```bash
# 确保 .env 中配置了 TS_AUTHKEY
docker compose -f docker-compose-tailscale.yml build
docker compose -f docker-compose-tailscale.yml up -d
docker logs -f glm-4.6v-nvfp4
```

等待日志显示 `Application startup complete` 即启动成功。

## API 使用

### 健康检查
```bash
curl http://localhost:8000/health
```

### 文本对话
```bash
curl http://localhost:8000/v1/chat/completions \
  -H "Content-Type: application/json" \
  -d '{
    "model": "GadflyII/GLM-4.6V-NVFP4",
    "messages": [{"role": "user", "content": "你好，请介绍一下你自己"}],
    "max_tokens": 512
  }'
```

### 图片理解
```bash
curl http://localhost:8000/v1/chat/completions \
  -H "Content-Type: application/json" \
  -d '{
    "model": "GadflyII/GLM-4.6V-NVFP4",
    "messages": [{
      "role": "user",
      "content": [
        {"type": "image_url", "image_url": {"url": "https://example.com/image.png"}},
        {"type": "text", "text": "描述这张图片"}
      ]
    }],
    "max_tokens": 1024
  }'
```

## 配置说明

| 参数 | 值 | 说明 |
|------|-----|------|
| `--max-model-len` | 131072 | 128K 上下文长度 |
| `--gpu-memory-utilization` | 0.95 | GPU 显存利用率 |
| `--tensor-parallel-size` | 1 | 单卡运行 |

## 常见问题及解决方案

### 1. `Expected ProcessorMixin but found PreTrainedTokenizerFast`

**原因：** vLLM 镜像内置的 transformers 版本过旧，不支持 GLM-4.6V。

**解决：** Dockerfile 已升级 transformers 到 5.0.0rc0。

### 2. 缺少 `preprocessor_config.json`

**原因：** 旧版 AWQ 量化模型仓库未包含此文件（NVFP4 版本已包含，无需此步骤）。

**解决：** 将本仓库提供的 `preprocessor_config.json` 复制到模型目录。

### 3. 使用 `--enforce-eager` 导致推理速度慢

**原因：** eager 模式禁用了 CUDA Graph。

**解决：** docker-compose.yml 已移除 `--enforce-eager`。首次启动需要编译图（约 2-3 分钟），之后推理速度更快。

## 停止服务

```bash
# 本地模式
docker compose down

# Tailscale 模式
docker compose -f docker-compose-tailscale.yml down
```

## 许可证

本部署配置按原样提供。GLM-4.6V 模型受其自身许可条款约束。
