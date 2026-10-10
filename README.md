<div align="center">

# ai-cli-setup

**一键安装并配置你的 AI CLI agent**

选 agent → 自动安装 → 统一配置 · 全自研 · 无上游脚本依赖

[![CI](https://github.com/zxfccmm4/ai-cli-setup/actions/workflows/ci.yml/badge.svg)](https://github.com/zxfccmm4/ai-cli-setup/actions/workflows/ci.yml)
[![Release](https://github.com/zxfccmm4/ai-cli-setup/actions/workflows/release.yml/badge.svg)](https://github.com/zxfccmm4/ai-cli-setup/actions/workflows/release.yml)
[![License: MIT](https://img.shields.io/badge/license-MIT-blue.svg)](LICENSE)

</div>

---

v2.0 全新架构：**不再包装任何第三方安装脚本**。安装走各 agent 官方渠道
（原生 installer / npm），配置文件由本脚本直接生成——一个脚本管到底。

## 快速开始

```bash
curl -fsSL https://raw.githubusercontent.com/zxfccmm4/ai-cli-setup/main/ai-cli-setup.sh | bash
```

```text
$ curl -fsSL .../ai-cli-setup.sh | bash

Select language  /  选择语言            ① 选语言
choose / 请选择 [1] 2

要安装哪些 AI agent？                  ② 选 agent：单选 / 多选 / 全部
  1) Pi           https://pi.dev
  2) OmO          https://omo.dev
  3) Claude Code  （仅 Linux/WSL）
  4) Codex CLI
  5) Grok Build
  6) OpenCode
  7) 以上全部
请选择 [7] 1,6
ℹ 已选择：Pi, OpenCode

==> 安装 Pi        …                    ③ 依次安装（官方渠道）
==> 安装 OpenCode

==> 凭据（只问一次，所有 agent 共用）    ④ 统一收集凭据
接口 base URL: https://gw.example.com/v1
API key: sk-************xyz            （显式掩码：前 3 + 后 3）
ℹ 发现 152 个模型 → 留空回车全选

==> 配置 Pi                              ⑤ 批量写配置
==> 配置 OpenCode
汇总：✓ Pi  ✓ OpenCode
```

| agent 菜单输入 | 含义 |
|---|---|
| `6` | 单选 |
| `1,3` / `1 3` / `1-3` | 多选（逗号、空格、区间混用） |
| `a` / `all` / `0` / `7` | 全部 |

## 支持的 agent

| agent | 安装渠道 | 配置文件 | 备注 |
|---|---|---|---|
| `pi` | `pi.dev/install.sh`（回退 npm） | `~/.pi/agent/{models,settings}.json` | |
| `omo` | `get.omo.dev/install.sh`（回退 npm） | `~/.omo/agent/{models,settings}.json` | root 需确认（自动） |
| `claude` | `claude.ai/install.sh`（回退 npm） | `~/.claude/settings.json` | **仅 Linux/WSL 安装** |
| `codex` | npm `@openai/codex` | `~/.codex/{config.toml,auth.json}` | |
| `grok` | `x.ai/cli/install.sh` | `~/.grok/config.toml` | 装到 `~/.grok/bin` |
| `opencode` | `opencode.ai/install`（回退 npm） | `~/.config/opencode/opencode.json` | 自动检测 V1/V2 格式；V2 时 key 走 `{env:}` 引用不落盘 |

macOS 上 `claude` 跳过安装（上游限制），但配置照常写入。

## 命令行用法

```bash
./ai-cli-setup.sh                          # 交互向导
./ai-cli-setup.sh pi,opencode              # 指定 agent
./ai-cli-setup.sh all                      # 全部
./ai-cli-setup.sh all -y \                 # 完全非交互
  --base-url https://gw.example.com/v1 \
  --api-key sk-xxxx \
  --models gpt-5.6,glm-5.3 \
  --model gpt-5.6                          # 默认模型（claude/codex/grok/opencode）
./ai-cli-setup.sh all --skip-install -y …  # 只配置不安装
./ai-cli-setup.sh all --dry-run …          # 只看计划
./ai-cli-setup.sh list                     # 已装 agent 一览
./ai-cli-setup.sh doctor                   # 环境体检
```

## 配置格式

统一凭据写入各 agent 的原生配置（均为原子写入 + `chmod 600` + 自动备份）：

| agent | 写入内容 |
|---|---|
| pi / omo | `models.json`：providers.{host} = { baseUrl, apiKey, models[] }；`settings.json`：defaultProvider/defaultModel |
| claude | `settings.json` 的 `env` 块：ANTHROPIC_BASE_URL / ANTHROPIC_AUTH_TOKEN / ANTHROPIC_MODEL |
| codex | `config.toml`：model_provider/model/model_providers.OpenAI.base_url；`auth.json`：OPENAI_API_KEY |
| grok | `config.toml`：models.default + model.{alias} = { model, base_url, api_key } |
| opencode | `opencode.json`：provider.{id}.options.{baseURL,apiKey} + models + model（合并，保留已有键） |

## 安全

- API key **显式掩码输入**：实时显示 `前3 + 星号 + 后3`，支持退格 / Ctrl-U；粘贴不闪现明文。
- 配置文件权限 `600`；写入前自动 `*.bak.<时间戳>` 备份。
- `--dry-run` 不落盘、不安装。

## 依赖 / 兼容性

- macOS / Linux，bash 3.2+；`curl` 或 `wget`。
- 配置生成需要 `node` 或 `python3`（pi/omo/opencode/claude 写 JSON）。
- `curl | bash` 管道模式交互读 `/dev/tty`；容器 / CI 用 `AICLI_ASSUME_TTY=1`。
- 安装 Node（nodesource）需要 root；omo root 安装自动加 `OMO_INSTALL_ALLOW_SUDO=1`。

## 环境变量

`AICLI_BASE_URL` `AICLI_API_KEY` `AICLI_MODELS` `AICLI_MODEL`
`AICLI_LANG`（en/zh）`AICLI_ASSUME_TTY`（1=stdin 当交互）
`GROK_ALIAS` `GROK_CONTEXT_WINDOW` `CODEX_WIRE_API`（responses/chat）
`AICLI_OPENCODE_V2`（1=强制写 V2 格式；默认按已装版本自动检测）

## 常见问题

<details><summary><b>看起来卡住了？</b></summary>

多半在等你回答：语言、agent、base URL、API key（掩码，输完回车）、模型列表（留空 = 全部）。
</details>

<details><summary><b>模型列表拉不到？</b></summary>

脚本带 key 请求 `<base_url>/v1/models`。失败常见原因：key 无效、URL 缺 `/v1`、网关不开放该接口。拉不到就手输模型 id。
</details>

<details><summary><b>只改配置不重装？</b></summary>

`./ai-cli-setup.sh <agent> --skip-install -y --base-url ... --api-key ...`
</details>

<details><summary><b>重跑会覆盖已有配置吗？</b></summary>

会先备份（`*.bak.<时间戳>`）再写。opencode 是合并写入，已有 plugin/provider 不丢。
</details>

## CI / Release

CI 每次推送跑：语法 + shellcheck、双平台冒烟、非交互全量写配置校验内容与权限、
交互流程（语言/agent/重试/掩码）、dry-run 不落盘、管道模式。

```bash
git tag v2.0.0 && git push origin v2.0.0   # 触发 Release
```

## CHANGELOG

由 [scripts/changelog.sh](scripts/changelog.sh) 从 git 历史生成（约定式提交，[Keep a Changelog](https://keepachangelog.com/)）。

## 许可

MIT。
