<div align="center">

# ai-cli-setup

**一个脚本，装好并配置你所有的 AI CLI agent**

选 agent → 自动安装 → 统一配置，凭据只问一次

[![CI](https://github.com/zxfccmm4/ai-cli-setup/actions/workflows/ci.yml/badge.svg)](https://github.com/zxfccmm4/ai-cli-setup/actions/workflows/ci.yml)
[![Release](https://github.com/zxfccmm4/ai-cli-setup/actions/workflows/release.yml/badge.svg)](https://github.com/zxfccmm4/ai-cli-setup/actions/workflows/release.yml)
[![License: MIT](https://img.shields.io/badge/license-MIT-blue.svg)](LICENSE)

</div>

---

```bash
curl -fsSL https://raw.githubusercontent.com/zxfccmm4/ai-cli-setup/main/ai-cli-setup.sh | bash
```

Pi、OmO、Claude Code、Codex、Grok Build、OpenCode 六个 agent，各走各的官方渠道安装，配置由本脚本直接生成——不包装任何第三方安装脚本，一条命令管到底。

## 长什么样

```text
$ curl -fsSL .../ai-cli-setup.sh | bash

Select language  /  选择语言
  1) English
  2) 中文 (Chinese)
choose / 请选择 2

要安装哪些 AI agent？
  1) Pi           https://pi.dev
  2) OmO          https://omo.dev
  3) Claude Code  （仅 Linux/WSL）
  4) Codex CLI    https://github.com/openai/codex
  5) Grok Build   https://x.ai/cli
  6) OpenCode     https://opencode.ai
  7) 以上全部

  单个数字 = 单选   |   1,3 或 1-3 = 多选   |   a 或 7 = 全部

请选择 7
ℹ  已选择：Pi, OmO, Claude Code, Codex CLI, Grok Build, OpenCode

==> 安装 Pi · OmO · Claude Code · Codex · Grok · OpenCode
    （官方渠道：官方 installer 或 npm，已装则自动跳过）

==> 凭据（只问一次，所有 agent 共用）
接口 base URL: https://gw.example.com/v1
API key: sk-**************xyz        ← 显式掩码，只显示前 3 后 3
ℹ  发现 152 个模型 → 留空回车全选，或手输需要的几个
默认模型 id: group/auto-claude-sonnet-5-5

==> 配置 Pi          ✓ ~/.pi/agent/{models,settings}.json
==> 配置 OmO         ✓ ~/.omo/agent/{models,settings}.json
==> 配置 Claude Code ✓ ~/.claude/settings.json
==> 配置 Codex       ✓ ~/.codex/{config.toml,auth.json}
==> 配置 Grok        ✓ ~/.grok/config.toml
==> 配置 OpenCode    ✓ ~/.config/opencode/opencode.json

汇总
────────────────────────────────────────────
  ✓  Pi           3s
  ✓  OmO          12s
  ✓  Claude Code  48s
  ✓  Codex CLI    5s
  ✓  Grok Build   2s
  ✓  OpenCode     8s
────────────────────────────────────────────
ℹ  配置成功 6 个，失败 0 个
```

## 支持的 agent

| agent | 安装渠道 | 配置文件 | 备注 |
|---|---|---|---|
| Pi | `pi.dev/install.sh`（回退 npm） | `~/.pi/agent/{models,settings}.json` | |
| OmO | `get.omo.dev`（回退 npm） | `~/.omo/agent/{models,settings}.json` | root 自动确认 |
| Claude Code | `claude.ai/install.sh`（回退 npm） | `~/.claude/settings.json` | 安装仅 Linux/WSL |
| Codex | npm `@openai/codex` | `~/.codex/{config.toml,auth.json}` | |
| Grok Build | `x.ai/cli/install.sh` | `~/.grok/config.toml` | |
| OpenCode | `opencode.ai/install`（回退 npm） | `~/.config/opencode/opencode.json` | 自动识别 V1/V2 格式，合并写入 |

## 三件事做完

1. **选**：语言 + agent（单选、多选、全部，无效输入重试 3 次）
2. **装**：每个 agent 走官方渠道；已装跳过；装完校验二进制真实可执行
3. **配**：凭据问一次，掩码输入；模型列表带 key 自动拉取；批量写入原生配置

**安全设计**：API key 掩码输入（前 3 + 星号 + 后 3，粘贴不闪明文）；配置文件权限 `600`，写入前自动时间戳备份；`--dry-run` 不落盘；OpenCode V2 的 key 只写 `{env:}` 引用、不落配置文件。

## 平台支持

| 环境 | 支持情况 |
|---|---|
| Linux（glibc） | 六个 agent 全部支持 |
| macOS | Claude Code 跳过安装仅写配置（上游限制），其余全部支持 |
| OpenWrt / musl 软路由 | Claude Code、OpenCode 实测可用（OpenCode 自动装官方 musl 构建）；Pi / OmO / Codex 依赖 Node.js，建议在 Debian 容器内运行 |

## 命令速查

```bash
./ai-cli-setup.sh                              # 交互向导
./ai-cli-setup.sh pi,opencode                  # 指定 agent
./ai-cli-setup.sh all -y \
  --base-url https://gw.example.com/v1 \
  --api-key sk-xxxx \
  --models gpt-5.6,glm-5.3 \
  --model gpt-5.6                              # 完全非交互
./ai-cli-setup.sh claude --skip-install ...    # 只刷配置不重装
./ai-cli-setup.sh all --dry-run ...            # 只看计划
./ai-cli-setup.sh list                         # 已装 agent 一览
./ai-cli-setup.sh doctor                       # 环境体检
```

## 常见问题

<details>
<summary><b>看起来卡住了？</b></summary>

大概率在等你回答。API key 输入时只显示掩码（`sk-***xyz`），你敲的字符不会原样出现，输完回车即可。模型列表一步留空回车等于全选。
</details>

<details>
<summary><b>Claude Code 界面正常，发消息却报模型错误？</b></summary>

默认模型留空时 Claude Code 会用官方模型名（如 `claude-opus-5-5`），自定义网关不认识这个名字。重跑配置，默认模型必须填网关上真实存在的 id。
</details>

<details>
<summary><b>软路由（OpenWrt）上 opencode 报 not found？</b></summary>

musl 系统装了 glibc 二进制时 exec 会失败，报错恰好是 "not found"。本脚本会自动检测 musl 并安装官方 musl 构建；若 PATH 未生效，先执行 `export PATH="$HOME/.opencode/bin:$PATH"`。
</details>

<details>
<summary><b>重跑会覆盖已有配置吗？</b></summary>

写前自动备份（`*.bak.<时间戳>`）。OpenCode 是合并写入，已有的 plugin、其他 provider 不会丢；Claude Code 无 node 时同样做键级合并。
</details>

## 环境变量 / CI / Release

<details>
<summary><b>环境变量</b></summary>

`AICLI_BASE_URL` `AICLI_API_KEY` `AICLI_MODELS` `AICLI_MODEL` `AICLI_LANG`（en/zh）
`AICLI_ASSUME_TTY`（1 = 把 stdin 当交互输入，容器 / CI 用）
`AICLI_OPENCODE_V2`（1 = 强制写 OpenCode V2 格式）
`GROK_ALIAS` `GROK_CONTEXT_WINDOW` `CODEX_WIRE_API`（responses/chat）
</details>

<details>
<summary><b>CI / Release / CHANGELOG</b></summary>

CI 双平台（Ubuntu / macOS 含 bash 3.2）跑语法、shellcheck、交互流程、隔离 HOME 真写配置校验内容与权限、dry-run、管道模式。推送 `v*.*.*` tag 触发 Release。`CHANGELOG.md` 由 `scripts/changelog.sh` 从 git 历史生成。
</details>

## 许可

MIT
