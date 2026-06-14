### OpenCode / Claude Code / agent 编程 参数选择

优先用这组：

{
  "temperature": 0.6,
  "top_p": 0.95,
  "top_k": 20,
  "presence_penalty": 0.0,
  "repetition_penalty": 1.0
}

原因是这正好对应 Qwen 官方给的“precise coding tasks”推荐。

复杂规划、架构设计、开放式方案比较

可以切到更发散一点的 thinking 参数：

{
  "temperature": 1.0,
  "top_p": 0.95,
  "top_k": 20,
  "presence_penalty": 1.5,
  "repetition_penalty": 1.0
}

这是官方给的 general thinking 方案。

非思考、想要更直接更短的回答

如果你的客户端支持切到 non-thinking 模式，再考虑：

{
  "temperature": 0.7,
  "top_p": 0.8,
  "top_k": 20,
  "presence_penalty": 1.5,
  "repetition_penalty": 1.0
}

不过 Qwen3.5 官方也明确说了，它不像 Qwen3 那样官方支持 /think 和 /nothink 的软切换，所以不同推理框架里这个“非思考模式”的实现方式不完全一样。