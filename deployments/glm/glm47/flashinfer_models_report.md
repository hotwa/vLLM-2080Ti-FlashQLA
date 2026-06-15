# FlashInfer 支持模型完整调研报告

## 一、硬性门槛

FlashInfer 只支持 head_dim ∈ **{64, 128, 256}**

计算公式: `head_dim = hidden_size / num_attention_heads`

---

## 二、完整支持模型列表

| 模型家族       | 具体型号            |   hidden_size |   num_attention_heads |   head_dim | FlashInfer支持   | 备注                          |
|:---------------|:--------------------|--------------:|----------------------:|-----------:|:-----------------|:------------------------------|
| LLaMA          | LLaMA-2-7B          |          4096 |                    32 |        128 | ✅               | 最主流的开源基座              |
| LLaMA          | LLaMA-2-13B         |          5120 |                    40 |        128 | ✅               |                               |
| LLaMA          | LLaMA-2-70B         |          8192 |                    64 |        128 | ✅               |                               |
| LLaMA          | LLaMA-3-8B          |          4096 |                    32 |        128 | ✅               |                               |
| LLaMA          | LLaMA-3-70B         |          8192 |                    64 |        128 | ✅               |                               |
| LLaMA          | LLaMA-3.1-8B        |          4096 |                    32 |        128 | ✅               | 128K上下文                    |
| LLaMA          | LLaMA-3.2-1B        |          2048 |                    32 |         64 | ✅               | head_dim=64                   |
| LLaMA          | LLaMA-3.2-3B        |          3072 |                    24 |        128 | ✅               |                               |
| Mistral        | Mistral-7B          |          4096 |                    32 |        128 | ✅               | 滑动窗口注意力                |
| Mistral        | Mistral-Small-24B   |          5120 |                    32 |        128 | ✅               | GQA, 32K上下文                |
| Mistral        | Mixtral-8x7B        |          4096 |                    32 |        128 | ✅               | MoE架构                       |
| Mistral        | Mixtral-8x22B       |          6144 |                    48 |        128 | ✅               | MoE架构                       |
| Qwen           | Qwen2-7B            |          3584 |                    28 |        128 | ✅               | GQA                           |
| Qwen           | Qwen2.5-7B          |          3584 |                    28 |        128 | ✅               |                               |
| Qwen           | Qwen2.5-14B         |          5120 |                    40 |        128 | ✅               |                               |
| Qwen           | Qwen2.5-32B         |          5120 |                    40 |        128 | ✅               |                               |
| Qwen           | Qwen2.5-72B         |          8192 |                    64 |        128 | ✅               |                               |
| Qwen           | Qwen3-4B            |          2560 |                    32 |        128 | ✅               |                               |
| Qwen           | Qwen3-8B            |          4096 |                    32 |        128 | ✅               |                               |
| CodeLlama      | CodeLlama-7B        |          4096 |                    32 |        128 | ✅               | 代码专用                      |
| CodeLlama      | CodeLlama-13B       |          5120 |                    40 |        128 | ✅               |                               |
| CodeLlama      | CodeLlama-34B       |          8192 |                    64 |        128 | ✅               |                               |
| DeepSeek-Coder | DeepSeek-Coder-6.7B |          4096 |                    32 |        128 | ✅               | v1标准注意力                  |
| DeepSeek-Coder | DeepSeek-Coder-33B  |          7168 |                    56 |        128 | ✅               | v1标准注意力                  |
| StarCoder2     | StarCoder2-7B       |          4608 |                    36 |        128 | ✅               | 代码模型                      |
| StarCoder2     | StarCoder2-15B      |          6144 |                    48 |        128 | ✅               |                               |
| Codestral      | Codestral-22B       |          6144 |                    48 |        128 | ✅               | Mistral代码模型               |
| Qwen-Coder     | Qwen2.5-Coder-7B    |          3584 |                    28 |        128 | ✅               | 强烈推荐用于Agent             |
| Qwen-Coder     | Qwen2.5-Coder-32B   |          5120 |                    40 |        128 | ✅               |                               |
| IBM Granite    | Granite-8B-Code     |          4096 |                    32 |        128 | ✅               | 企业级代码模型                |
| IBM Granite    | Granite-20B-Code    |          6144 |                    48 |        128 | ✅               |                               |
| IBM Granite    | Granite-4.0         |          5120 |                    40 |        128 | ✅               | 128K上下文                    |
| Yi             | Yi-6B               |          4096 |                    32 |        128 | ✅               |                               |
| Yi             | Yi-34B              |          7168 |                    56 |        128 | ✅               |                               |
| InternLM       | InternLM2-7B        |          4096 |                    32 |        128 | ✅               | GQA                           |
| InternLM       | InternLM2-20B       |          6144 |                    48 |        128 | ✅               |                               |
| Baichuan       | Baichuan2-7B        |          4096 |                    32 |        128 | ✅               |                               |
| Baichuan       | Baichuan2-13B       |          5120 |                    40 |        128 | ✅               |                               |
| Falcon         | Falcon-7B           |          4544 |                    71 |         64 | ✅               | head_dim=64优化FlashAttention |
| Falcon         | Falcon-40B          |          8192 |                   128 |         64 | ✅               |                               |
| Falcon         | Falcon-180B         |         14848 |                   232 |         64 | ✅               |                               |
| OPT            | OPT-125M            |           768 |                    12 |         64 | ✅               | 小模型                        |
| OPT            | OPT-1.3B            |          2048 |                    32 |         64 | ✅               |                               |
| OPT            | OPT-2.7B            |          2560 |                    32 |         80 | ❌               | head_dim=80不支持             |
| OPT            | OPT-6.7B            |          4096 |                    32 |        128 | ✅               |                               |
| Mamba          | Mamba-Codestral-7B  |          4096 |                   128 |         64 | ✅               | SSM架构，非Transformer        |
| GPT-J          | GPT-J-6B            |          4096 |                    16 |        256 | ✅               | 经典开源模型                  |
| GPT-NeoX       | GPT-NeoX-20B        |          6144 |                    24 |        256 | ✅               | EleutherAI                    |
| Gemma          | Gemma-2B            |          2048 |                     8 |        256 | ✅               | 部分版本                      |
| Gemma          | Gemma-7B            |          3072 |                    16 |        192 | ❌               | head_dim=192不支持！          |
| Gemma          | Gemma-2-9B          |          3584 |                    16 |        224 | ❌               | head_dim=224不支持            |
| Gemma          | Gemma-2-27B         |          4608 |                    32 |        144 | ❌               | head_dim=144不支持            |
| DeepSeek-V2    | DeepSeek-Coder-V2   |          5120 |                   128 |        128 | ⚠️               | MLA架构，qk_nope_head_dim=128 |
| DeepSeek-V2    | DeepSeek-V2-Lite    |          2048 |                   128 |        128 | ⚠️               | MLA架构，需特殊处理           |
| GLM            | GLM-4.7-Flash       |          6144 |                    32 |        192 | ❌               | qk_nope_head_dim=192不支持    |

---

## 三、适合 Agent 的 Code 模型推荐

| 推荐等级   | 模型                      |   head_dim | 上下文   | FlashInfer   | Agent适用性   | 特点                             | 显存需求   |
|:-----------|:--------------------------|-----------:|:---------|:-------------|:--------------|:---------------------------------|:-----------|
| ⭐⭐⭐⭐⭐ | Qwen2.5-Coder-7B-Instruct |        128 | 128K     | ✅           | 极高          | 代码修复/测试补全/CI自愈最稳定   | ~16GB      |
| ⭐⭐⭐⭐   | CodeLlama-7B-Instruct     |        128 | 16K      | ✅           | 高            | 生态好，工具链成熟               | ~16GB      |
| ⭐⭐⭐⭐   | StarCoder2-7B             |        128 | 16K      | ✅           | 高            | 代码补全能力强                   | ~16GB      |
| ⭐⭐⭐⭐   | DeepSeek-Coder-6.7B       |        128 | 16K      | ✅           | 高            | 工程向，长代码理解好             | ~16GB      |
| ⭐⭐⭐     | Granite-8B-Code           |        128 | 128K     | ✅           | 中高          | IBM企业级，长上下文              | ~18GB      |
| ⭐⭐⭐⭐   | Mamba-Codestral-7B        |         64 | 256K     | ✅           | 高            | SSM架构，推理极快，HumanEval 75% | ~16GB      |
| ⭐⭐⭐⭐⭐ | StarCoder2-15B            |        128 | 16K      | ✅           | 极高          | 复杂重构/多文件修改能力强        | ~32GB      |
| ⭐⭐⭐⭐⭐ | Codestral-22B             |        128 | 32K      | ✅           | 极高          | Mistral专用代码模型，多语言支持  | ~48GB      |
| ⭐⭐⭐⭐   | Granite-20B-Code          |        128 | 8K       | ✅           | 高            | 企业级，稳定可靠                 | ~45GB      |
| ⭐⭐⭐     | Mistral-Small-24B         |        128 | 32K      | ✅           | 中高          | 通用+代码均衡，工具调用原生支持  | ~50GB      |
| ⭐⭐⭐⭐⭐ | Qwen2.5-Coder-32B         |        128 | 128K     | ✅           | 极高          | 大工程理解，一次生成完整模块     | ~80GB      |
| ⭐⭐⭐⭐   | DeepSeek-Coder-33B        |        128 | 16K      | ✅           | 高            | v1标准注意力，工程任务强         | ~80GB      |
| ⭐⭐⭐⭐   | CodeLlama-34B             |        128 | 16K      | ✅           | 高            | 大模型稳定性好                   | ~80GB      |

---

## 四、不支持 FlashInfer 的模型

| 模型          |   head_dim | 问题                                  | 替代方案                                               |
|:--------------|-----------:|:--------------------------------------|:-------------------------------------------------------|
| Gemma-7B      |        192 | head_dim=192 不在 FlashInfer 支持列表 | 使用 Gemma-2B (head_dim=256) 或其他 7B 模型            |
| Gemma-2-9B    |        224 | head_dim=224 不在 FlashInfer 支持列表 | 使用 Qwen2.5-7B 或 CodeLlama-7B                        |
| Gemma-2-27B   |        144 | head_dim=144 不在 FlashInfer 支持列表 | 使用 Qwen2.5-32B 或 CodeLlama-34B                      |
| GLM-4.7-Flash |        192 | qk_nope_head_dim=192，MLA结构不支持   | 使用标准注意力模型如 Qwen2.5                           |
| OPT-2.7B      |         80 | head_dim=80 不在 FlashInfer 支持列表  | 使用 OPT-1.3B (head_dim=64) 或 OPT-6.7B (head_dim=128) |

---

## 五、vLLM 启动配置示例

### Qwen2.5-Coder-7B
```bash
python -m vllm.entrypoints.openai.api_server \
  --model Qwen/Qwen2.5-Coder-7B-Instruct \
  --attention-backend FLASHINFER \
  --tensor-parallel-size 1 \
  --max-model-len 32768
```

### Codestral-22B
```bash
python -m vllm.entrypoints.openai.api_server \
  --model mistralai/Codestral-22B-v0.1 \
  --attention-backend FLASHINFER \
  --tensor-parallel-size 2 \
  --max-model-len 32768
```

### Qwen2.5-Coder-32B
```bash
python -m vllm.entrypoints.openai.api_server \
  --model Qwen/Qwen2.5-Coder-32B-Instruct \
  --attention-backend FLASHINFER \
  --tensor-parallel-size 2 \
  --max-model-len 131072
```

---

## 六、快速检测代码

```python
import json
from pathlib import Path

def check_flashinfer_compatibility(config_path):
    with open(config_path, 'r') as f:
        config = json.load(f)

    hidden_size = config.get('hidden_size', config.get('n_embd', 0))
    num_heads = config.get('num_attention_heads', config.get('n_head', 0))
    head_dim = config.get('head_dim', hidden_size // num_heads if num_heads else 0)

    SUPPORTED_HEAD_DIMS = {64, 128, 256}
    is_supported = head_dim in SUPPORTED_HEAD_DIMS

    return {
        'model': config.get('model_type', 'unknown'),
        'head_dim': head_dim,
        'flashinfer_supported': is_supported
    }
```

---

## 七、关键结论

### ✅ 完全支持 (head_dim ∈ {64, 128, 256})
- **head_dim=64**: Falcon系列, OPT小模型, Mamba-Codestral, LLaMA-3.2-1B
- **head_dim=128**: LLaMA全系, Mistral/Mixtral, Qwen全系, CodeLlama, StarCoder2, Codestral, Granite, Yi, InternLM, Baichuan2
- **head_dim=256**: GPT-J-6B, GPT-NeoX-20B, Gemma-2B

### ❌ 不支持 (head_dim ∉ {64, 128, 256})
- **Gemma-7B**: head_dim=192
- **Gemma-2-9B**: head_dim=224
- **Gemma-2-27B**: head_dim=144
- **GLM-4.7-Flash**: head_dim=192
- **OPT-2.7B**: head_dim=80

### ⚠️ MLA架构需特殊处理
- **DeepSeek-Coder-V2**: qk_nope_head_dim=128
- **DeepSeek-V2-Lite**: qk_nope_head_dim=128

---

*报告生成时间: 2026-02-06*
