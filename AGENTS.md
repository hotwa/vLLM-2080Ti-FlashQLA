# AGENTS.md

This file governs the whole `vLLM 2080 Ti Definitive Edition` repository.

## Project Identity And Credit

This repository is a hardware-focused fork for dual RTX 2080 Ti / SM75 vLLM
serving. It builds on upstream vLLM and preserves the local runtime work,
profiles, documentation, and benchmark evidence needed to reproduce the 2080 Ti
stack.

If you publish, redistribute, repackage, benchmark, or build a derivative from
this repository, keep clear credit to:

- Upstream vLLM and its original license.
- `vLLM 2080 Ti Definitive Edition`.
- The repository author: `github.com/weicj`.

Do not remove existing attribution, license notices, benchmark provenance, or
project identity text. If you maintain a public derivative, state that it is
based on this project unless the code has been independently replaced.

## Upstream Compatibility

This project remains a fork of upstream vLLM. When changing source files that
come from upstream vLLM:

- Preserve upstream license and copyright notices.
- Prefer small, reviewable patches over broad rewrites.
- Keep SM75/Turing-specific behavior guarded or clearly documented.
- Do not present fork-specific behavior as upstream vLLM behavior.
- If an upstream `AGENTS.md` or contribution instruction applies in a copied
  upstream subtree, follow it as well.

## Runtime And Profile Rules

This repository is organized around validated runtime routes, not generic
benchmark guesses.

- Do not invent context-size, throughput, or support claims without evidence.
- Keep profile files focused on route parameters only. Do not store global
  service settings such as GPU selection, port, chat template, or reasoning
  defaults inside route profiles.
- Use `profiles/README.md`, `profiles/README.zh-CN.md`, and
  `docs/model-profile-routes.md` as the source of truth for shipped profiles.
- If adding or promoting a profile, include capacity evidence and throughput
  evidence using the repository's documented benchmark口径.
- Do not keep tiny smoke-only profiles as recommended deployment presets.

## Validation Before Publishing

Before committing or publishing changes, run the relevant subset of:

```bash
bash -n build.sh launcher.sh tools/validate_profiles.sh
bash tools/validate_profiles.sh
python3 -m py_compile <changed-python-files>
git diff --check
```

For launcher/profile changes, also verify `launcher.sh --print-config` for the
affected route and mode. For runtime kernel or graph-policy changes, include a
real benchmark or smoke result that proves the changed path still works.

## Documentation Discipline

- Keep English and Simplified Chinese documentation consistent when both exist.
- Keep benchmark numbers tied to the exact model, KV precision, MTP setting,
  context, and benchmark method.
- Restore or update linked assets when moving documentation. Broken benchmark
  figures are treated as documentation regressions.
- Avoid overstating support. Use precise wording such as `validated`,
  `supported`, `experimental`, or `not promoted` according to the evidence.

## Repository Structure

```
.
├── .github/workflows/          # CI/CD（Docker 镜像构建等）
├── .dockerignore               # Docker 忽略规则（必须在根目录）
├── AGENTS.md                   # 本文件：仓库治理规则
├── build.sh                    # 上游构建脚本
├── launcher.sh                 # 上游启动脚本
├── CMakeLists.txt              # 上游构建系统
├── setup.py / pyproject.toml   # Python 包构建
├── csrc/                       # CUDA/C++ 源码（上游）
├── vllm/                       # Python 源码（上游）
├── profiles/                   # 运行时 profile（上游）
├── requirements/               # Python 依赖（上游）
├── tests/                      # 测试（上游）
├── tools/                      # 工具脚本（上游）
├── cmake/                      # CMake 模块（上游）
├── FlashQLA-SM70-SM75/         # 子模块
├── docs/                       # 文档
│
├── docker/                     # ★ Docker 配置
│   ├── Dockerfile              #   多阶段构建（CI 通过 file: docker/Dockerfile 引用）
│   ├── docker-compose.yml      #   服务编排 Safe Profile（docker compose -f docker/docker-compose.yml）
│   ├── docker-compose-fast.yml #   Fast Profile（INT8 KV Cache）
│   ├── docker-entrypoint.sh    #   容器入口脚本
│   └── chat_template_no_thinking.jinja  # 禁用 thinking 的聊天模板
│
├── deployments/                # ★ 各部署项目（每个子目录独立）
│   ├── qwen/                   #   Qwen 系列部署配置
│   ├── glm/                    #   GLM 系列部署配置
│   ├── ikllama/                #   ik_llama.cpp 部署配置
│   ├── qwen36-a3b-ikllama-dual2080ti/
│   ├── qwopus-glm18b-ikllama/
│   ├── CoPaw-ik/
│   ├── IQuest-Coder/
│   ├── gpt-oss-120b/
│   ├── w8a8/
│   └── google/
│
└── scripts/                    # ★ 运行/辅助脚本
    ├── run_qwen27b_fast.sh     #   Qwen 27B Fast 模式启动脚本
    └── run_qwen27b_safe.sh     #   Qwen 27B Safe 模式启动脚本
```

标 `★` 的目录为用户自定义内容，其余为上游 vLLM 标准结构。

### 目录使用规范

**`docker/`** — 所有 Docker 相关配置归入此目录。

- 构建镜像：`docker build -f docker/Dockerfile .`（上下文为仓库根目录）
- 启动服务：`docker compose -f docker/docker-compose.yml up -d`
- CI 通过 `.github/workflows/docker-build.yml` 自动构建，已配置 `file: docker/Dockerfile`

**`deployments/`** — 各部署项目独立子目录，互不干扰。

- 每个子目录包含自己的 Dockerfile、docker-compose、脚本、配置等
- 新增部署项目时，在 `deployments/<项目名>/` 下创建
- 不要将上游 vLLM 源码文件放入此目录

**`scripts/`** — 仓库级别的运行脚本。

- 脚本内部使用 `SCRIPT_DIR/..` 定位仓库根目录
- 脚本通过 `cd` 到仓库根目录后执行，依赖 `.venv/bin/python` 等根目录资源

### 路径引用注意事项

| 场景 | 路径写法 |
|------|----------|
| docker-compose volume（从 docker/ 引用根目录） | `../qwen/models:/models` |
| Dockerfile ENTRYPOINT | `/opt/vllm/docker/docker-entrypoint.sh` |
| CI build-push-action | `file: docker/Dockerfile` |
| scripts 中定位仓库根目录 | `cd "$SCRIPT_DIR/.."` |

### 根目录文件保留规则

以下文件保持根目录位置（上游标准或被工具引用）：

- `build.sh`、`launcher.sh` — 上游工具脚本，被 AGENTS.md 和 CI 引用
- `CMakeLists.txt`、`setup.py`、`pyproject.toml` — 构建系统
- `.dockerignore` — Docker 要求在构建上下文根目录
- `README.md`、`LICENSE`、`CHANGELOG.md`、`VERSION` — 项目文档

## Repository Hygiene

- Do not commit local caches, model weights, logs, temporary workspace state,
  run outputs, or generated native build artifacts.
- Keep `README.md`, `README.zh-CN.md`, `CHANGELOG.md`, `VERSION`, and
  `pyproject.toml` version fallback aligned for releases.
- Release tags and GitHub Releases are separate. Pushing a tag is not enough to
  update the GitHub Release page.
