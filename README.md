<div align="center">

# ⚡ ai-cli-setup

**一个脚本，装好并统一配置你所有的 AI CLI Agent**

选 Agent ➔ 官方渠道自动安装 ➔ 统一配置 · 凭据只问一次

[![CI](https://img.shields.io/github/actions/workflow/status/zxfccmm4/ai-cli-setup/ci.yml?branch=main&label=CI&logo=github&style=flat-square)](https://github.com/zxfccmm4/ai-cli-setup/actions/workflows/ci.yml)
[![Release](https://img.shields.io/github/v/release/zxfccmm4/ai-cli-setup?label=Release&color=blue&style=flat-square)](https://github.com/zxfccmm4/ai-cli-setup/releases)
[![Bash](https://img.shields.io/badge/bash-3.2%2B-green.svg?style=flat-square&logo=gnu-bash)](https://www.gnu.org/software/bash/)
[![Platform](https://img.shields.io/badge/platform-Linux%20%7C%20macOS%20%7C%20musl-lightgrey.svg?style=flat-square)](https://github.com/zxfccmm4/ai-cli-setup)
[![License: MIT](https://img.shields.io/badge/license-MIT-blue.svg?style=flat-square)](LICENSE)

<br />

```bash
curl -fsSL https://raw.githubusercontent.com/zxfccmm4/ai-cli-setup/main/ai-cli-setup.sh | bash
```

一条命令搞定 **Pi**、**OmO**、**OMP**、**Claude Code**、**Codex**、**Grok Build**、**OpenCode** 7 大主流 CLI Agent。<br />
各走官方渠道安装，原生配置自动生成，无第三方包装脚本，纯 Bash 实现。

<br />
</div>

---

## ✨ 核心特性

- 🎯 **一键统管 7 大主流 Agent**：支持 Pi、OmO、OMP、Claude Code、Codex、Grok Build、OpenCode，按需多选或全选安装。
- 🔑 **凭据只问一次**：Base URL 与 API Key 统一采集，一键批量分发写入各 Agent 的原生配置格式（JSON / TOML / YAML）。
- 📡 **智能拉取模型**：配置时自动请求网关端点拉取模型列表，一键全选或交互式挑选。
- 🔒 **银行级安全防护**：
  - **交互动态掩码**：API Key 实时渲染为 `sk-******xyz`，粘贴及输入均不闪现明文。
  - **严格权限隔离**：所有生成的敏感配置文件权限均强制设为 `600`。
  - **零风险回退**：覆盖前自动创建带时间戳的备份副本；提供 `--dry-run` 预览落盘计划（零落盘、零副作用）。
  - **OpenCode V2 机制保护**：Key 支持通过 `{env:}` 环境变量引用导出，不直接硬编码在配置文件中。
- 🧩 **合并写入，不丢配置**：OpenCode / Claude Code / OMP 均按键级合并，已有插件、MCP、其它 Provider 与主题设置原样保留。
- 🐧 **极致兼容**：全面适配 Linux (glibc)、macOS (arm64/x86_64) 及 OpenWrt / Alpine 等 musl 软路由架构；无 node 的精简系统有纯 Bash 兜底。

---

## 🖥 终端交互效果

```text
$ curl -fsSL .../ai-cli-setup.sh | bash

Select language  /  选择语言
  1) English
  2) 中文 (Chinese)
choose / 请选择 2

要安装哪些 AI agent？
  1) Pi           https://pi.dev
  2) OmO          https://omo.dev
  3) OMP          https://omp.sh
  4) Claude Code  （仅 Linux/WSL）
  5) Codex CLI    https://github.com/openai/codex
  6) Grok Build   https://x.ai/cli
  7) OpenCode     https://opencode.ai
  8) 以上全部

  单个数字 = 单选   |   1,3 或 1-3 = 多选   |   a 或 8 = 全部

请选择 8
ℹ  已选择：Pi, OmO, OMP, Claude Code, Codex CLI, Grok Build, OpenCode

==> 安装 Pi · OmO · OMP · Claude Code · Codex · Grok · OpenCode
    （官方渠道：官方 installer 或 npm，已装则自动跳过）

==> 凭据（只问一次，所有 agent 共用）
接口 base URL: https://gw.example.com/v1
API key: sk-**************xyz        ← 实时掩码输入，保护密钥安全
ℹ  发现 152 个模型 → 留空回车全选，或手输需要的几个
默认模型 id: group/auto-claude-sonnet-5-5

==> 配置 Pi          ✓ ~/.pi/agent/{models,settings}.json
==> 配置 OmO         ✓ ~/.omo/agent/{models,settings}.json
==> 配置 OMP         ✓ ~/.omp/agent/{models.yml,config.yml}
==> 配置 Claude Code ✓ ~/.claude/settings.json
==> 配置 Codex       ✓ ~/.codex/{config.toml,auth.json}
==> 配置 Grok        ✓ ~/.grok/config.toml
==> 配置 OpenCode    ✓ ~/.config/opencode/opencode.json

汇总
────────────────────────────────────────────
  ✓  Pi           3s
  ✓  OmO          12s
  ✓  OMP          9s
  ✓  Claude Code  48s
  ✓  Codex CLI    5s
  ✓  Grok Build   2s
  ✓  OpenCode     8s
────────────────────────────────────────────
ℹ  配置成功 7 个，失败 0 个
```

---

## 📦 支持的 Agent 矩阵

| Agent | 官方安装渠道 | 配置文件位置 | 配置格式 | 特别说明 |
| :--- | :--- | :--- | :---: | :--- |
| **Pi** | npm `@earendil-works/pi-coding-agent`（回退 `pi.dev/install.sh`） | `~/.pi/agent/{models,settings}.json` | `JSON` | 自动配置 Provider 与默认模型 |
| **OmO** | `get.omo.dev`（回退 npm） | `~/.omo/agent/{models,settings}.json` | `JSON` | root 用户下自动授权执行 |
| **OMP** | `omp.sh/install`（回退 bun / npm） | `~/.omp/agent/{models.yml,config.yml}` | `YAML` | 保留 `modelRoles` 其它角色与主题设置；密钥强制 600 |
| **Claude Code** | `claude.ai/install.sh`（回退 npm） | `~/.claude/settings.json` | `JSON` | 安装仅支持 Linux/WSL；macOS 仅写配置 |
| **Codex CLI** | npm `@openai/codex` | `~/.codex/{config.toml,auth.json}` | `TOML` / `JSON` | 自动写入模型映射与 Base URL |
| **Grok Build** | `x.ai/cli/install.sh` | `~/.grok/config.toml` | `TOML` | 自动配置模型别名与上下文窗口 |
| **OpenCode** | `opencode.ai/install`（回退 npm） | `~/.config/opencode/opencode.json` | `JSON` | 自动识别 V1 / V2 规范并无损合并 |

---

## 🌍 系统与环境支持

| 环境平台 | 支持情况 | 说明 |
| :--- | :---: | :--- |
| **Linux (glibc)** | ✅ **全部支持** | Ubuntu, Debian, CentOS, Fedora, Arch 等全特性支持 |
| **macOS** | ✅ **全部支持** | 原生兼容；Claude Code 跳过安装阶段仅写配置（上游官方限制） |
| **OpenWrt / musl 软路由** | ⚡ **深度优化** | 自动识别 musl 架构并安装官方 musl 构建；Pi/OmO/OMP/Codex 依赖 Node，会优雅跳过安装但仍写配置（建议在容器运行） |

---

## 🚀 常用命令速查

### 1. 交互与常规使用

```bash
# 引导式交互模式（首选，含语言选择）
./ai-cli-setup.sh

# 指定仅安装并配置某几个 agent
./ai-cli-setup.sh pi,opencode
```

### 2. 自动化部署与 CI

```bash
# 完全非交互静默安装配置全部 agent
./ai-cli-setup.sh all -y \
  --base-url https://gw.example.com/v1 \
  --api-key sk-xxxx \
  --models gpt-5.6,glm-5.3 \
  --model gpt-5.6

# 仅更新配置文件，跳过二进制下载与安装
./ai-cli-setup.sh claude --skip-install

# 仅预览执行计划，不落盘、不修改任何现有文件
./ai-cli-setup.sh all --dry-run
```

### 3. 环境与诊断工具

```bash
# 查看本地已安装的 agent 状态及路径
./ai-cli-setup.sh list

# 运行全面的本地环境体检（探测依赖命令、路径、配置文件完整性）
./ai-cli-setup.sh doctor
```

---

## ❓ 常见问题 (FAQ)

<details>
<summary><b>输入 API Key 时界面好像卡住了？</b></summary>
<br />

这是正常的安全保护机制。为了防止旁人偷窥或录屏泄露，输入密钥时终端启用掩码模式，只会显示 `sk-******xyz`。按键与粘贴均不会回显明文字符，输入完成后直接按回车即可。
</details>

<details>
<summary><b>Claude Code 界面正常，但对话时报错提示模型不存在？</b></summary>
<br />

当默认模型留空时，Claude Code 会尝试使用官方模型名（例如 `claude-opus-5-5`），部分第三方网关无法识别此名称。脚本现在**要求必须提供默认模型**（`--model`，或自动取 `--models` 的第一个）；若仍有问题，请用 `--model <网关上的真实模型 ID>` 重新运行。
</details>

<details>
<summary><b>OMP 的密钥为什么是明文写在 <code>models.yml</code> 里？</b></summary>
<br />

这是 OMP 的限制：它的 `models.yml` **不做环境变量插值**（写 `${VAR}` 会被原样当成密钥发送），也没有 OpenCode 那样的 `{env:}` 引用语法。脚本因此把密钥明文写入并强制 `chmod 600` 保护该文件。
</details>

<details>
<summary><b>软路由 (OpenWrt) 上运行 OpenCode 报 <code>not found</code>？</b></summary>
<br />

musl 系统若误安装了 glibc 预编译二进制，在动态链接器缺失时系统会报错 `not found`。本脚本内置了对 musl 架构的精准识别并拉取官方 musl 构建。若命令无法直接调用，请在新开终端执行 `export PATH="$HOME/.opencode/bin:$PATH"`。
</details>

<details>
<summary><b>重复执行脚本会冲掉现有的配置或插件吗？</b></summary>
<br />

不会。写入新配置前会自动对原文件建立时间戳备份（`*.bak.<timestamp>`）。对于 OpenCode、Claude Code 与 OMP，脚本会做键级/块级增量合并——已有插件、MCP、其它 Provider、`theme`、以及 `modelRoles` 里的 `smol`/`slow` 等角色都不会丢失。
</details>

---

## ⚙️ 环境变量速查

| 环境变量 | 作用说明 | 默认值 / 选项 |
| :--- | :--- | :--- |
| `AICLI_BASE_URL` | 网关 API Base URL（例如 `https://api.example.com/v1`） | - |
| `AICLI_API_KEY` | 网关 API 密钥 | - |
| `AICLI_MODELS` | 注册的模型列表（逗号分隔） | 自动从端点拉取 |
| `AICLI_MODEL` | 默认模型 ID | 模型列表首项 |
| `AICLI_LANG` | 界面语言 | `zh` 或 `en` |
| `AICLI_ASSUME_TTY` | 将标准输入视作 TTY 终端（容器 / CI 环境使用） | `0` / `1` |
| `AICLI_OPENCODE_V2` | 强制采用 OpenCode V2 格式（使用 `{env:}` 凭据引用） | 自动探测 / `1` |
| `GROK_ALIAS` | Grok CLI 默认模型别名 | `main` |
| `GROK_CONTEXT_WINDOW`| Grok CLI 上下文窗口尺寸 | `500000` |
| `CODEX_WIRE_API` | Codex CLI 协议类型 | `responses` / `chat` |

---

## 📚 详细文档

- 📘 [快速上手指南 (Quick Start)](docs/quickstart.md)
- ⚙️ [配置与参数详解 (Configuration)](docs/configuration.md)
- 🛠 [疑难问题与排错 (Troubleshooting)](docs/troubleshooting.md)
- 💻 [本地开发与发版规范 (Development)](docs/development.md)

---

## 📄 开源许可证

本项目基于 [MIT License](LICENSE) 开源。
