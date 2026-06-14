FROM vllm/vllm-openai:v0.19.0-cu130-ubuntu2404

RUN pip install --no-cache-dir "transformers==5.5.0"

ENV VLLM_NVFP4_GEMM_BACKEND=cutlass

RUN python3 - <<'PYEOF'
import os
import vllm

base = vllm.__path__[0]

# Blackwell TMA patch from the model card guidance.
utils_path = os.path.join(base, "model_executor/layers/fla/ops/utils.py")
with open(utils_path, "r", encoding="utf-8") as f:
    utils_src = f.read()

old = "is_nvidia and torch.cuda.get_device_capability(0)[0] >= 9"
new = "is_nvidia and 9 <= torch.cuda.get_device_capability(0)[0] < 12"
if old in utils_src and new not in utils_src:
    utils_src = utils_src.replace(old, new, 1)
    with open(utils_path, "w", encoding="utf-8") as f:
        f.write(utils_src)
    print("[PATCH] Applied Blackwell TMA patch")
else:
    print("[PATCH] TMA patch already present or anchor changed")

target = os.path.join(base, "model_executor/models/qwen3_5.py")
patch = r'''
# ===== HOTFIX: minimal text-only fallback for Qwen3.5 on v0.19.x =====
try:
    from types import SimpleNamespace
    import torch.nn as nn
    import vllm.model_executor.models.qwen3_5 as _q35_mod

    _orig_init = _q35_mod.Qwen3_5ForConditionalGeneration.__init__

    def _patched_init(self, *, vllm_config, prefix="model"):
        cfg = vllm_config.model_config.hf_config

        # Prefer the upstream path when a real multimodal config is present.
        if hasattr(cfg, "vision_config"):
            return _orig_init(self, vllm_config=vllm_config, prefix=prefix)

        from vllm.model_executor.models.qwen3_5 import (
            Qwen3_5ForCausalLM,
            maybe_prefix,
        )

        for name in (
            "video_token_id",
            "image_token_id",
            "vision_token_id",
            "vision_start_token_id",
            "vision_end_token_id",
            "vision_pad_token_id",
        ):
            if not hasattr(cfg, name):
                setattr(cfg, name, -1)

        nn.Module.__init__(self)
        self.update_packed_mapping(enable_lora=vllm_config.lora_config is not None)

        mm_cfg = getattr(vllm_config.model_config, "multimodal_config", None)
        if mm_cfg is None:
            mm_cfg = SimpleNamespace(mm_encoder_tp_mode="weights")

        self.config = cfg
        self.multimodal_config = mm_cfg
        self.use_data_parallel = False
        self.is_multimodal_pruning_enabled = False
        self.visual = None
        self.language_model = Qwen3_5ForCausalLM(
            vllm_config=vllm_config,
            prefix=maybe_prefix(prefix, "language_model"),
        )
        self.make_empty_intermediate_tensors = (
            self.language_model.make_empty_intermediate_tensors
        )
        print("[HOTFIX] minimal text-only Qwen3.5 fallback enabled")

    _q35_mod.Qwen3_5ForConditionalGeneration.__init__ = _patched_init
    print("[PATCH] qwen3_5.py minimal fallback appended")
except Exception as e:
    print("[HOTFIX WARN]", repr(e))
# ===== END HOTFIX =====
'''

with open(target, "a", encoding="utf-8") as f:
    f.write("\n" + patch + "\n")

print("Done.")
PYEOF
