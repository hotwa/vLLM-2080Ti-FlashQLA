FROM vllm/vllm-openai:nightly

# 升级 transformers 到 5.0.0rc0（GLM-4.6V 必须，忽略 vLLM 的版本限制）
RUN pip install -U --pre "transformers==5.2.0" tokenizers accelerate \
    && python3 -c "import transformers; print('transformers:', transformers.__version__)"
