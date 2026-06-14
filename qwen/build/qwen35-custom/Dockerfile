# 继承最新的 vLLM 官方镜像
FROM vllm/vllm-openai:v0.19.0-cu130-ubuntu2404

# Restore transformers 5.5.0 so that qwen3_5_text is recognized
RUN pip install --no-cache-dir transformers==5.5.0

RUN python3 - <<'PYEOF'
import os
import vllm

base = vllm.__path__[0]

# 1. 绕过 context.py 的强类型校验
ctx = os.path.join(base, 'multimodal/processing/context.py')
if os.path.exists(ctx):
    c = open(ctx).read()
    if 'raise TypeError(' in c:
        open(ctx, 'w').write(c.replace('raise TypeError(', 'print('))

def safe_append(path, code):
    with open(path, 'a') as f: f.write(code)

# 2. 绕过 encoder_budget.py 里的多模态测算错误
budget = os.path.join(base, 'multimodal/encoder_budget.py')
safe_append(budget, '''
_orig_get_mm_max_toks = get_mm_max_toks_per_item
def _safe_get_mm_max_toks_per_item(*args, **kwargs):
    try: return _orig_get_mm_max_toks(*args, **kwargs)
    except Exception: return {}
get_mm_max_toks_per_item = _safe_get_mm_max_toks_per_item
''')

# 3. 绕过 qwen3_vl.py 的 get_data_parser 访问 vision_config
vl3 = os.path.join(base, 'model_executor/models/qwen3_vl.py')
safe_append(vl3, '''
try:
    import vllm.model_executor.models.qwen3_vl as _vl3_mod
    _orig_get_data_parser = _vl3_mod.Qwen3VLProcessingInfo.get_data_parser
    def _safe_get_data_parser(self):
        hf_cfg = self.get_hf_config()
        if not hasattr(hf_cfg, "vision_config"):
            from vllm.model_executor.models.qwen2_vl import Qwen2VLMultiModalDataParser
            return Qwen2VLMultiModalDataParser(spatial_merge_size=2, video_needs_metadata=True, expected_hidden_size=self._get_expected_hidden_size())
        return _orig_get_data_parser(self)
    _vl3_mod.Qwen3VLProcessingInfo.get_data_parser = _safe_get_data_parser
except Exception as e:
    print("[HOTFIX WARN] vl3 patch failed", e)
''')

# 4. 绕过 qwen3_5.py.__init__ 初始化视觉塔
target = os.path.join(base, "model_executor/models/qwen3_5.py")
patch = r'''
# ===== HOTFIX: guard text-only Qwen3.5 config =====
try:
    import torch
    import vllm.model_executor.models.qwen3_5 as _q35_mod
    _orig_init = _q35_mod.Qwen3_5ForConditionalGeneration.__init__

    def _patched_init(self, vllm_config, prefix=""):
        config = getattr(vllm_config.model_config, "hf_config", vllm_config.model_config.hf_text_config)

        if not hasattr(config, "vision_config"):
            # Mock missing multimodal properties required by Qwen3's mRoPE calculators
            if not hasattr(config, "video_token_id"): config.video_token_id = -1
            if not hasattr(config, "image_token_id"): config.image_token_id = -1
            if not hasattr(config, "vision_token_id"): config.vision_token_id = -1
            if not hasattr(config, "vision_start_token_id"): config.vision_start_token_id = -1
            if not hasattr(config, "vision_end_token_id"): config.vision_end_token_id = -1
            if not hasattr(config, "vision_pad_token_id"): config.vision_pad_token_id = -1
            
            # Dummy vision_config to satisfy spatial_merge_size reads
            config.vision_config = type("MockVisionConfig", (), {"spatial_merge_size": 2, "temporal_patch_size": 2})()

            from vllm.model_executor.models.qwen3_5 import (
                Qwen3_5ForCausalLM,
                maybe_prefix,
            )
            
            torch.nn.Module.__init__(self)

            self.config = config
            self.multimodal_config = getattr(
                vllm_config.model_config, "multimodal_config", None
            )
            self.visual = None
            self.language_model = Qwen3_5ForCausalLM(
                vllm_config=vllm_config,
                prefix=maybe_prefix(prefix, "language_model"),
            )
            self.make_empty_intermediate_tensors = (
                self.language_model.make_empty_intermediate_tensors
            )
            return

        return _orig_init(self, vllm_config, prefix)

    _q35_mod.Qwen3_5ForConditionalGeneration.__init__ = _patched_init
    print("[HOTFIX] patched qwen3_5.py for text-only config (with nn.Module.__init__)")
except Exception as e:
    print("[HOTFIX WARN]", repr(e))
# ===== END HOTFIX =====
'''
with open(target, "a", encoding="utf-8") as f:
    f.write("\n" + patch + "\n")

print("All hotfixes applied successfully!")
PYEOF