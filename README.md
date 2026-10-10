<div align="center">

# ai-cli-setup

**一个脚本，装好你所有的 AI CLI agent**

English / 中文 · 凭据只问一次 · 一个失败不影响下一个

[![CI](https://github.com/zxfccmm4/ai-cli-setup/actions/workflows/ci.yml/badge.svg)](https://github.com/zxfccmm4/ai-cli-setup/actions/workflows/ci.yml)
[![Release](https://github.com/zxfccmm4/ai-cli-setup/actions/workflows/release.yml/badge.svg)](https://github.com/zxfccmm4/ai-cli-setup/actions/workflows/release.yml)
[![License: MIT](https://img.shields.io/badge/license-MIT-blue.svg)](LICENSE)

</div>

---

把 **zxfccmm4** 的 5 个 AI CLI 一键安装脚本（Pi / OmO / Claude Code / Codex / Grok Build）
加上 **OpenCode**，整合成**一个入口**。只做编排，不修改任何上游代码。

## 快速开始

```bash
# 远程一行（推荐）
curl -fsSL https://raw.githubusercontent.com/zxfccmm4/ai-cli-setup/main/ai-cli-setup.sh | bash

# 或本地
chmod +x ai-cli-setup.sh && ./ai-cli-setup.sh
```

运行后依次回答两个问题，其余全自动：

```text
❯ ./ai-cli-setup.sh

Select language  /  选择语言

  1) English
  2) 中文 (Chinese)

choose / 请选择 [1] 2

要配置哪些 AI agent？

  1) Pi           https://pi.dev
  2) OmO          https://omo.dev
  3) Claude Code  https://claude.ai/code
  4) Codex CLI    https://github.com/openai/codex
  5) Grok Build   https://x.ai/cli
  6) OpenCode     https://opencode.ai
  7) 以上全部

  单个数字 = 单选   |   1,3 或 1-3 = 多选   |   a 或 7 = 全部

请选择 [7] 1,6
✔ 已选择：Pi, OpenCode
…填一次 base_url + api_key，两个 agent 依次装好并配置
```

| 输入 | 含义 |
|---|---|
| `6` | 只装 OpenCode |
| `1,3` / `1 3` / `1-3` | 多选：Pi、Claude Code（或范围 Pi→Claude Code） |
| `a` / `all` / `0` / `7` | 全部 |

输入无效时最多重试 3 次。选「全部」时推荐序与单选一致。

## 支持的 agent

| agent | 来源 | 配置文件 |
|---|---|---|
| `pi` | [zxfccmm4/pi-setup](https://github.com/zxfccmm4/pi-setup) · [pi.dev](https://pi.dev) | `~/.pi/agent/{models,settings}.json` |
| `omo` | [zxfccmm4/omo-setup](https://github.com/zxfccmm4/omo-setup) · [omo.dev](https://omo.dev) | `~/.omo/agent/*`、`~/.omo/omo.jsonc` |
| `claude` | [zxfccmm4/claude-code-linux-installer](https://github.com/zxfccmm4/claude-code-linux-installer) · [Claude Code](https://claude.com/product/claude-code) | shell 配置或 `~/.claude/settings.json` |
| `codex` | [zxfccmm4/deploy-codex](https://github.com/zxfccmm4/deploy-codex) | `~/.codex/{config.toml,auth.json}` |
| `grok` | [zxfccmm4/GrokBuild](https://github.com/zxfccmm4/GrokBuild) | `~/.grok/config.toml` |
| `opencode` | 本脚本内置实现（无上游仓库） | `~/.config/opencode/opencode.json` |

`opencode` 由本脚本实现：官方 installer（`https://opencode.ai/install`）装 CLI，
失败回退 `npm i -g opencode-ai`，然后**合并**写入 `opencode.json`
（已有的 `plugin` / `mcp` / 其他 provider 全部保留）。

## 命令行用法

不想走菜单？全部可以绕过：

```bash
./ai-cli-setup.sh all                          # 全部
./ai-cli-setup.sh pi                           # 单个
./ai-cli-setup.sh pi,claude                    # 多个（逗号分隔）
./ai-cli-setup.sh all --skip claude,codex      # 全部但跳过两个
./ai-cli-setup.sh all --only pi,grok           # 只跑这两个
```

### 完全非交互（脚本化 / 多机部署）

```bash
./ai-cli-setup.sh all -y \
  --base-url https://gw.example.com/v1 \
  --api-key sk-xxxx \
  --models gpt-5.6,gpt-5.5,claude-sonnet-4-5
```

- `-y` / `--yes`：非交互模式，缺 `--base-url` / `--api-key` 会直接报错。
- 模型列表默认会自动请求 `<base_url>/v1/models` 拉取，拉不到就需要 `--models` 指定。
- 单个 agent 的更多例子（`--grok-search on`、`--opencode-method npm`、`--pin` 等）
  见 `./ai-cli-setup.sh --help`。

### 更多命令

```bash
./ai-cli-setup.sh doctor          # 环境体检：依赖、已装 CLI、配置文件
./ai-cli-setup.sh list            # 工具清单 + 上游版本 + 缓存状态
./ai-cli-setup.sh download all    # 预下载全部上游脚本（离线可用）
./ai-cli-setup.sh codex -- --restore   # "--" 之后原样透传给上游脚本
./ai-cli-setup.sh all --dry-run   # 只打印计划，不落盘
```

## 工作原理

1. **选语言**：English / 中文，后续所有提示与向导统一语言（`--lang` 或 `AICLI_LANG` 可跳过此步）。
2. **选 agent**：单个 / 多个 / 全部，支持序号、逗号、区间、别名（详见上文）。
3. **问一次凭据**：`base_url` + `api_key`，自动拉取模型列表让你挑；拉不到就手输 `--models`。
4. **翻译成各家变量**：统一凭据映射为各上游认识的环境变量 / 配置文件——

   | 统一参数 | pi | omo | claude | codex | grok | opencode |
   |---|---|---|---|---|---|---|
   | `--base-url` | `PISETUP_BASE_URL` | `OMO_BASE_URL` | `CLAUDE_BASE_URL` | `CODEX_BASE_URL` | 写入 config.toml | `provider.options.baseURL` |
   | `--api-key` | `PISETUP_API_KEY` | `OMO_API_KEY` | `CLAUDE_API_KEY` | `CODEX_API_KEY` | 写入 config.toml | `provider.options.apiKey` |
   | `--models` | `PISETUP_MODELS` | `OMO_MODELS` | — | — | — | `provider.models` + `model` |

5. **取上游脚本**：优先仓库内 `upstream/<repo>/` 快照（离线可用）；
   否则下载到 `~/.cache/ai-cli-setup/<repo>@<ref>/`（raw.githubusercontent.com → jsDelivr 自动切换）。
6. **逐个执行**：独立子 shell，一个失败不影响下一个（`--fail-fast` 可改为立即停止）。
7. **汇总**：成功 / 失败 + 耗时。

## 安全

- API key 交互输入不回显，日志一律打码（`前4****后4`）。
- 写入的配置权限 `600`，写入前自动 `*.bak.<时间戳>` 备份。
- `--dry-run` 只打印计划，不写文件、不装软件。
- `--pin` + `VERSIONS.md` 可把上游固定到已验证提交。

## 兼容性 / 依赖

- macOS / Linux，bash 3.2+（无需 `brew install bash`）。
- `curl` 或 `wget` 必需；opencode 配置写入需要 `node`；grok/codex 的 TOML/JSON 校验需要 `python3`。
- `curl | bash` 管道模式下交互读 `/dev/tty`；容器 / CI 无 `/dev/tty` 时用
  `AICLI_ASSUME_TTY=1`（或 `--assume-tty`）把 stdin 当交互输入。
- Linux 上安装 Codex 需要 `root` / `sudo`。

## 环境变量

| 组 | 变量 |
|---|---|
| 凭据 | `AICLI_BASE_URL` `AICLI_API_KEY` `AICLI_MODELS` `AICLI_MODEL` |
| 行为 | `AICLI_LANG`（en/zh，设置后跳过语言选择）`AICLI_ASSUME_TTY` `AICLI_REF` `AICLI_CACHE_DIR` `AICLI_RAW_HOST` `AICLI_JSD_HOST` `AICLI_OWNER` |
| grok | `AICLI_GROK_ALIAS` `AICLI_GROK_SEARCH` `AICLI_GROK_CONTEXT_WINDOW` |
| opencode | `AICLI_OPENCODE_CONFIG` `AICLI_OPENCODE_PROVIDER` `AICLI_OPENCODE_PROVIDER_NAME` `AICLI_OPENCODE_NPM` `AICLI_OPENCODE_METHOD` `AICLI_OPENCODE_INSTALL_URL` |

## CI / Release

CI（`.github/workflows/ci.yml`）每次 push / PR 跑：

- 全部自有脚本 `bash -n` + `shellcheck`（上游快照只做信息性检查）
- Ubuntu + macOS（含系统 bash 3.2）双平台冒烟测试
- **交互流程测试**：语言选择、agent 单选 / 多选 / 全部、无效输入重试、`--lang` 跳过
- 隔离 `$HOME` 里真写一次 `opencode.json` 与 `~/.grok/config.toml`，校验内容 / `600` 权限 / 备份 / 合并不丢键
- `--dry-run` 不落盘、`-y` 缺凭据报错、未知工具被拒、管道模式可用

推送 `v*.*.*` tag 触发 Release（详见 [.github/workflows/release.yml](.github/workflows/release.yml)）：

```bash
git tag v1.1.0 && git push origin v1.1.0
```

产物：`ai-cli-setup.sh`（单文件可直接用，找不到本地快照时自动下载上游）、
`changelog.sh`、`SHA256SUMS`、`VERSION.txt`、`CHANGELOG.md`、`README.md`、`LICENSE`。

校验：`chmod +x ai-cli-setup.sh && sha256sum -c SHA256SUMS`

## CHANGELOG

`CHANGELOG.md` 由 [scripts/changelog.sh](scripts/changelog.sh) 从 git 历史生成（约定式提交），
遵循 [Keep a Changelog](https://keepachangelog.com/)：

```bash
./scripts/changelog.sh                                    # 打印 [Unreleased]
./scripts/changelog.sh --all --update CHANGELOG.md        # 按 tag 重建并写回（幂等）
```

## 许可

MIT。五个上游仓库均为 MIT，版权归各自作者所有。OpenCode 版权归其作者所有。
