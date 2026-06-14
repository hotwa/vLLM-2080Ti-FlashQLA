2) 常见“能吃到 FLASHINFER”的模型家族（举例）

下面这些家族里，绝大多数主流规格 head_dim=128（因此非常常见地符合）：

LLaMA 系列（LLaMA 2 / 3 / 3.1 / 3.2 等，很多都是 128）

Mistral / Mixtral（常见 128）

Qwen2 / Qwen2.5（大量规格是 128）

Yi、InternLM2、Baichuan2（不少配置也是 128）

另外还有一些经典架构也经常命中 64 或 256：

Falcon 7B / 40B（很多是 head_dim=64）

GPT-J 6B（常见 head_dim=256）

OPT 系列不少小中型（常见 head_dim=64）

相反，你当前这条 GLM-4.7-Flash MLA（你这里提到的 qk_nope_head_dim=192），即使不谈 MLA，192 也不在 FlashInfer 标准注意力的 head_dim 支持列表里，所以它“结构性吃不到”这条优化。

小心一个坑：像 Gemma 7B 这类常见 head_dim=192 的，就会直接不匹配（因此不属于“FlashInfer 友好型”）。
｜
给我详细调研一下都能吃到FLASHINFER的模型？适合 agent 调用的 code 模型
回答：
下面这份是“**能稳定吃到 vLLM 的 `FLASHINFER`（非-MLA standard attention backend）**”的 **code 模型调研清单**，并且我会优先挑**适合 agent 调用**（指令/工具调用/修复代码/长上下文工程任务常用）的型号。

---

## 0) 先把硬门槛钉死：FLASHINFER 只认哪些 head_dim？

在 vLLM 的 FlashInfer backend 里，`get_supported_head_sizes()` 目前返回的是：

**head_dim ∈ {64, 128, 256}** ([vLLM][1])

> 实操上：你只要拿模型的 `config.json` 算 `hidden_size / num_attention_heads`（或同义字段 `n_embd / n_head`），落在 64/128/256，就属于“FlashInfer 友好型”。

---

## 1) 最适合做 agent 的“主力 code 模型”（基本都 head_dim=128）

这些模型家族的主流规格，head_dim 基本稳定命中 128，因此很适合你在 **SM75（2080 Ti）** 上把 attention backend 固定为 `FLASHINFER` 来吃收益（当然也要看你的 vLLM build 里 FlashInfer 是否编进去了）。

### A) Qwen2.5-Coder（强烈推荐给 agent）

* **Qwen/Qwen2.5-Coder-7B-Instruct**：`hidden_size=3584, num_attention_heads=28 → head_dim=128` ([Hugging Face][2])
* **Qwen/Qwen2.5-Coder-32B**：`hidden_size=5120, num_attention_heads=40 → head_dim=128` ([Hugging Face][3])

**为什么适合 agent**：Coder 系列对“改代码/补测试/读日志修 bug/多文件重构”的稳定性通常更好（你做 Ralph loop 这类 CI 自愈非常吃这一点）。

---

### B) CodeLlama（稳、生态好）

* **codellama/CodeLlama-7b-Instruct-hf**：`hidden_size=4096`（配套 Llama 架构常见 `num_attention_heads=32 → head_dim=128`） ([Hugging Face][4])

---

### C) DeepSeek-Coder（v1 & v2 都很“工程向”）

* **deepseek-coder-6.7b-base**：`hidden_size=4096, num_attention_heads=32 → head_dim=128` ([Hugging Face][5])
* **DeepSeek-Coder-V2-Instruct（MoE）**：它的 MLA 相关维度在 config 里直接写了：`qk_nope_head_dim=128`，并且 `hidden_size=5120, num_attention_heads=128 → 每头 40`（这里是 DeepSeekV2/MLA 特殊结构；但 **qk_nope_head_dim=128** 这一点对你判“128 友好”非常关键） ([Hugging Face][6])

> 你当前踩坑的 GLM-4.7-Flash MLA 是 192；而 DeepSeek-Coder-V2 这一支的 MLA 关键维度反而是 128，更“吃得到”优化路径（当然是不是走 FlashInfer 取决于你在 vLLM 里选的是哪条 attention 实现链路）。

---

### D) StarCoder2（代码基准常客，推理也好配）

* **bigcode/starcoder2-7b**：`hidden_size=4608, num_attention_heads=36 → head_dim=128` ([Hugging Face][7])
* **bigcode/starcoder2-15b**：`hidden_size=6144, num_attention_heads=48 → head_dim=128` ([Hugging Face][8])

---

### E) Codestral（偏“代码助手/补全/修复”的 22B）

* **mistralai/Codestral-22B-v0.1**：`hidden_size=6144, num_attention_heads=48 → head_dim=128` ([Hugging Face][9])

---

### F) IBM Granite Code（代码任务专门家族）

* **ibm-granite/granite-8b-code-base-4k**：`hidden_size=4096, num_attention_heads=32 → head_dim=128` ([Hugging Face][10])
* **ibm-granite/granite-20b-code-instruct-8k**：`n_embd=6144, n_head=48 → head_dim=128` ([Hugging Face][11])

---

## 2) 你要的“适合 agent 调用”的筛选建议（别只看能不能 FlashInfer）

你做的是 **长时间跑、读日志、改代码、改 CI、直到绿** 的 agent loop。除了 head_dim 命中 64/128/256 之外，我建议你按下面三档选（全部都在上面清单里覆盖了）：

### 7B–8B（单卡/低延迟，最适合高频工具调用）

* Qwen2.5-Coder-7B-Instruct ([Hugging Face][2])
* CodeLlama-7B-Instruct ([Hugging Face][4])
* StarCoder2-7B ([Hugging Face][7])
* Granite-8B-Code ([Hugging Face][10])

### 15B–22B（更强的规划/重构能力，适合“复杂 PR 修复”）

* StarCoder2-15B ([Hugging Face][8])
* Codestral-22B ([Hugging Face][9])
* Granite-20B-Code-Instruct ([Hugging Face][11])

### 32B 以上（大工程/更少回合数，但更吃显存/并行）

* Qwen2.5-Coder-32B ([Hugging Face][3])

---

## 3) 最快落地：让 agent 自动“判定并挑 FlashInfer 友好模型”

你可以让 agent 在本地扫一遍模型目录（每个目录的 `config.json`），把 **head_dim=64/128/256** 的 code 模型挑出来，然后优先用这些模型跑你的 loop。

判定依据就是 vLLM FlashInfer backend 的 head size 白名单：**[64, 128, 256]** ([vLLM][1])

---

如果你把你本地“准备给 agent 用的 code 模型列表”（文件夹名或 HuggingFace repo 名）贴出来，我可以直接给你输出一份**可执行的推荐矩阵**（每个模型：head_dim、上下文长度字段、是否 Instruct、适合做 planner 还是 fixer、以及你在 SM75 上建议固定 `FLASHINFER` 还是改走 `TRITON_ATTN`）。

[1]: https://docs.vllm.ai/en/v0.10.0/api/vllm/v1/attention/backends/flashinfer.html?utm_source=chatgpt.com "vllm.v1.attention.backends.flashinfer"
[2]: https://huggingface.co/Qwen/Qwen2.5-Coder-7B-Instruct/blame/8d20e2b046afe44cb4f759cff10574b995c0ddb8/config.json?utm_source=chatgpt.com "config.json · Qwen/Qwen2.5-Coder-7B-Instruct at ..."
[3]: https://huggingface.co/Qwen/Qwen2.5-Coder-32B/blob/main/config.json?utm_source=chatgpt.com "config.json · Qwen/Qwen2.5-Coder-32B at main"
[4]: https://huggingface.co/codellama/CodeLlama-7b-Instruct-hf/blob/main/config.json?utm_source=chatgpt.com "config.json · codellama/CodeLlama-7b-Instruct-hf at main"
[5]: https://huggingface.co/deepseek-ai/deepseek-coder-6.7b-base/blob/main/config.json?utm_source=chatgpt.com "config.json · deepseek-ai/deepseek-coder-6.7b-base at main"
[6]: https://huggingface.co/deepseek-ai/DeepSeek-Coder-V2-Instruct/blob/main/config.json "config.json · deepseek-ai/DeepSeek-Coder-V2-Instruct at main"
[7]: https://huggingface.co/bigcode/starcoder2-7b/blob/main/config.json?utm_source=chatgpt.com "config.json · bigcode/starcoder2-7b at main"
[8]: https://huggingface.co/bigcode/starcoder2-15b/blob/main/config.json?utm_source=chatgpt.com "config.json · bigcode/starcoder2-15b at main"
[9]: https://huggingface.co/mistralai/Codestral-22B-v0.1/blame/refs%2Fpr%2F56/config.json?utm_source=chatgpt.com "config.json · mistralai/Codestral-22B-v0.1 at refs/pr/56"
[10]: https://huggingface.co/ibm-granite/granite-8b-code-base-4k/blob/main/config.json?utm_source=chatgpt.com "config.json · ibm-granite/granite-8b-code-base-4k at main"
[11]: https://huggingface.co/ibm-granite/granite-20b-code-instruct-8k/blob/main/config.json "config.json · ibm-granite/granite-20b-code-instruct-8k at main"
