# Claude Code + LiteLLM 路由配置指南

## 架构概览

```
Claude Code → Tailscale VPN → LiteLLM (4000) → vLLM/llama.cpp
                           │
                    ┌──────┴──────┐
                    ↓             ↓
            claude-3-5-sonnet  claude-haiku-4-5-20251001
                    ↓             ↓
              vLLM (GLM)      llama.cpp 集群 LB
                            100.64.0.4:8080
                            100.64.0.14:8080
                            100.64.0.16:8080
```

## Claude Code 环境变量配置

在 `~/.bashrc` 或启动脚本中设置：

```bash
# LiteLLM 网关地址 (Tailscale IP)
export LOCAL_BASE_URL="http://100.64.0.5:4000"

# 主力模型 → vLLM/GLM
export LOCAL_MODEL="claude-3-5-sonnet"

# 快速模型 → llama.cpp 集群 (负载均衡)
export LOCAL_SMALL_FAST_MODEL="claude-haiku-4-5-20251001"

# API Key (LITELLM_MASTER_KEY)
export ANTHROPIC_API_KEY="sk-e03ecc69af774e76a0dcff922bda9d8c"
```

## 验证请求

```bash
# 测主力 (vLLM)
curl -s "$LOCAL_BASE_URL/v1/messages" \
  -H "Content-Type: application/json" \
  -H "x-api-key: $ANTHROPIC_API_KEY" \
  -d '{"model": "'"$LOCAL_MODEL"'", "max_tokens": 64, "messages": [{"role": "user", "content": "say hi"}]}'

# 测快模 (llama.cpp LB)
curl -s "$LOCAL_BASE_URL/v1/messages" \
  -H "Content-Type: application/json" \
  -H "x-api-key: $ANTHROPIC_API_KEY" \
  -d '{"model": "'"$LOCAL_SMALL_FAST_MODEL"'", "max_tokens": 64, "messages": [{"role": "user", "content": "say hi quickly"}]}'
```

---

## 负载均衡扩展指南

当需要添加新的 llama.cpp 后端时，只需修改 `litellm-config.yaml`。

### 添加新后端步骤

#### 1. 确认 llama.cpp 端点可用

```bash
curl -s http://<NEW_IP>:<PORT>/v1/messages -X POST \
  -H "Content-Type: application/json" \
  -d '{"model": "qwen3-code-flash", "max_tokens": 10, "messages": [{"role": "user", "content": "hi"}]}'
```

返回 Anthropic Messages 格式响应即可。

#### 2. 编辑 litellm-config.yaml

在 `model_list` 中找到 `claude-haiku-4-5-20251001` 部分，添加新条目：

```yaml
  # ===== 快模：claude-haiku-4-5-20251001 -> llama.cpp 集群 =====
  - model_name: claude-haiku-4-5-20251001
    litellm_params:
      model: anthropic/qwen3-code-flash
      api_base: http://100.64.0.4:8080  # 第1台
      api_key: anything
      timeout: 180
      drop_params: true

  - model_name: claude-haiku-4-5-20251001
    litellm_params:
      model: anthropic/qwen3-code-flash
      api_base: http://100.64.0.14:8080  # 第2台
      api_key: anything
      timeout: 180
      drop_params: true

  - model_name: claude-haiku-4-5-20251001
    litellm_params:
      model: anthropic/qwen3-code-flash
      api_base: http://100.64.0.16:8080  # 第3台
      api_key: anything
      timeout: 180
      drop_params: true

  # ========== 新增第4台 ==========
  - model_name: claude-haiku-4-5-20251001
    litellm_params:
      model: anthropic/qwen3-code-flash
      api_base: http://100.64.0.X:8080  # 替换为新IP
      api_key: anything
      timeout: 180
      drop_params: true
```

#### 3. 重启 LiteLLM 容器

```bash
cd /srv/project/vllm/glm46v
docker compose -f docker-compose-tailscale.yml restart litellm-router
```

#### 4. 验证负载均衡生效

连续发多个请求，检查响应：

```bash
for i in {1..6}; do
  curl -s "$LOCAL_BASE_URL/v1/messages" \
    -H "Content-Type: application/json" \
    -H "x-api-key: $ANTHROPIC_API_KEY" \
    -d '{"model": "'"$LOCAL_SMALL_FAST_MODEL"'", "max_tokens": 10, "messages": [{"role": "user", "content": "hi"}]}' | \
    jq -r '.model'
done
```

### 路由策略说明

当前配置使用 `simple-shuffle` 策略：

```yaml
router_settings:
  routing_strategy: simple-shuffle
```

| 策略 | 说明 |
|------|------|
| `simple-shuffle` | 轮询分配请求到多个后端（当前使用） |
| `least-requests` | 分配给请求数最少的后端 |
| `latency-based` | 分配给延迟最低的后端 |

---

## 添加全新模型别名

如果需要新增一个模型路由（比如 `claude-opus`），在 `model_list` 中添加：

```yaml
  # ===== 新模型别名 =====
  - model_name: claude-opus
    litellm_params:
      model: anthropic/<ACTUAL_MODEL_NAME>
      api_base: http://<TARGET_IP>:<PORT>
      api_key: anything
      timeout: 300
      drop_params: true
```

然后重启 LiteLLM，Claude Code 即可使用 `LOCAL_MODEL=claude-opus`。

---

## 故障排查

| 问题 | 可能原因 | 解决方式 |
|------|----------|----------|
| 请求返回 404 | 模型名未匹配 | 检查 `model_name` 是否拼写正确 |
| 请求返回 401 | API Key 错误 | 确认 `ANTHROPIC_API_KEY` 与 `LITELLM_MASTER_KEY` 一致 |
| 请求超时 | 后端无响应 | 检查对应 IP:Port 的 llama.cpp/vLLM 是否存活 |
| 负载均衡不生效 | 同一 `model_name` 条目不足 2 条 | 确认有至少 2 条相同 `model_name` 的配置 |

查看 LiteLLM 日志：

```bash
docker logs -f litellm-router
```