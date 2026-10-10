# ai-cli-setup

[![CI](https://github.com/zxfccmm4/ai-cli-setup/actions/workflows/ci.yml/badge.svg)](https://github.com/zxfccmm4/ai-cli-setup/actions/workflows/ci.yml)
[![Release](https://github.com/zxfccmm4/ai-cli-setup/actions/workflows/release.yml/badge.svg)](https://github.com/zxfccmm4/ai-cli-setup/actions/workflows/release.yml)
[![Latest release](https://img.shields.io/github/v/release/zxfccmm4/ai-cli-setup?sort=semver&color=2F81F7)](https://github.com/zxfccmm4/ai-cli-setup/releases/latest)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](./LICENSE)
[![Platform](https://img.shields.io/badge/platform-Linux%20%7C%20macOS-lightgrey)](./README.md#兼容性)
[![Shell](https://img.shields.io/badge/shell-bash%203.2%2B-4EAA25?logo=gnubash&logoColor=white)](./ai-cli-setup.sh)

把 **zxfccmm4** 的 5 个 AI CLI 一键安装脚本（Pi / OmO / Claude Code / Codex / Grok Build）
加上 **OpenCode**，整合成 **一个入口**：凭据只问一次，六个工具依次装好，最后给一份汇总。

> 本脚本只做「编排」，**不修改任何上游代码**。前五个工具仍由它们自己的官方脚本安装；
> `opencode` 上游没有对应仓库，由本脚本内置实现。

📖 **详细文档：[`docs/`](./docs/)** —— [快速上手](./docs/quickstart.md) ·
[配置详解](./docs/configuration.md) · [常见问题](./docs/troubleshooting.md) ·
[开发与发布](./docs/development.md)

## 整合了哪些仓库

| 工具 | 上游仓库 | 装什么 | 配置文件 |
|---|---|---|---|
| `pi` | [zxfccmm4/pi-setup](https://github.com/zxfccmm4/pi-setup) | Pi（[pi.dev](https://pi.dev)） | `~/.pi/agent/{models.json,settings.json}` |
| `omo` | [zxfccmm4/omo-setup](https://github.com/zxfccmm4/omo-setup) | OmO（[omo.dev](https://omo.dev)） | `~/.omo/agent/*`、`~/.omo/omo.jsonc` |
| `claude` | [zxfccmm4/claude-code-linux-installer](https://github.com/zxfccmm4/claude-code-linux-installer) | Claude Code（Linux / WSL） | shell 配置或 `~/.claude/settings.json` |
| `codex` | [zxfccmm4/deploy-codex](https://github.com/zxfccmm4/deploy-codex) | Codex CLI | `~/.codex/{config.toml,auth.json}` |
| `grok` | [zxfccmm4/GrokBuild](https://github.com/zxfccmm4/GrokBuild) | Grok Build CLI | `~/.grok/config.toml` |
| `opencode` | *(无上游仓库，本脚本内置)* | OpenCode（[opencode.ai](https://opencode.ai)） | `~/.config/opencode/opencode.json` |

> `opencode` 不属于 zxfccmm4 系列仓库，由本脚本自己实现：官方 installer
> （`https://opencode.ai/install`）装 CLI，失败回退 `npm i -g opencode-ai`，
> 然后合并写入 `opencode.json`。

## 快速开始

```bash
# 交互式：选工具 → 填 base_url / api_key → 开装
./ai-cli-setup.sh

# 全部装（凭据只问一次，模型列表自动从端点拉取）
./ai-cli-setup.sh all

# 远程一行（等价于下载后运行）
curl -fsSL https://raw.githubusercontent.com/zxfccmm4/ai-cli-setup/main/ai-cli-setup.sh | bash -s -- all
```

## 常用姿势

```bash
# 完全非交互
./ai-cli-setup.sh all -y \
  --base-url https://gw.example.com/v1 \
  --api-key sk-xxxx \
  --models gpt-5.6,gpt-5.5,claude-sonnet-4-5

# 只装 Pi，指定模型
./ai-cli-setup.sh pi -y --base-url https://gw.example.com/v1 \
  --api-key sk-xxxx --models gpt-5,gpt-5-mini

# Grok Build，开启服务端搜索（web_search / x_search）
./ai-cli-setup.sh grok -y --base-url https://gw.example.com/v1 \
  --api-key sk-xxxx --grok-search on --grok-alias MyGrok

# 只装 OpenCode，接自定义 OpenAI 兼容网关
./ai-cli-setup.sh opencode -y --base-url https://gw.example.com/v1 \
  --api-key sk-xxxx --models gpt-5,gpt-5-mini

# 指定 provider id / 安装方式
./ai-cli-setup.sh opencode -y --base-url https://my.gw.io/v1 --api-key sk-xxxx \
  --models a --opencode-provider mygw --opencode-method npm

# 跳过某个工具 / 只跑一部分
./ai-cli-setup.sh all --skip claude,codex
./ai-cli-setup.sh all --only pi,grok

# 只改配置、不重装 CLI
./ai-cli-setup.sh all --skip-install -y --base-url ... --api-key ...

# 先看看会做什么（不落盘）
./ai-cli-setup.sh all -y --base-url ... --api-key ... --dry-run

# 把参数透传给上游脚本本身
./ai-cli-setup.sh codex -- --restore
./ai-cli-setup.sh codex -- --uninstall

# 环境体检 / 查看缓存 / 预下载
./ai-cli-setup.sh doctor
./ai-cli-setup.sh list
./ai-cli-setup.sh download all

# 可复现安装（锁定已验证提交，见 VERSIONS.md）
./ai-cli-setup.sh all --pin
```

## 它到底做了什么

1. **选工具**：`all` / 单个 / `--only` / `--skip` / 交互菜单。
2. **问一次凭据**：`base_url` + `api_key`，自动请求 `<base_url>/v1/models`
   拉模型列表让你挑（拉不到就手输 `--models`）。
3. **翻译成各家变量**：把统一凭据映射为上游各自认识的环境变量 / 参数，例如

   | 统一 | pi | omo | claude | codex | grok | opencode |
   |---|---|---|---|---|---|---|
   | `--base-url` | `PISETUP_BASE_URL` | `OMO_BASE_URL` | `CLAUDE_BASE_URL` | `CODEX_BASE_URL` | 写入 `config.toml` | `provider.options.baseURL` |
   | `--api-key` | `PISETUP_API_KEY` | `OMO_API_KEY` | `CLAUDE_API_KEY` | `CODEX_API_KEY` | 写入 `config.toml` | `provider.options.apiKey` |
   | `--models` | `PISETUP_MODELS` | `OMO_MODELS` | — | — | — | `provider.models` + `model` |

4. **取上游脚本**：优先用仓库内 `upstream/<repo>/` 的快照；
   否则下载到 `~/.cache/ai-cli-setup/<repo>@<ref>/`
   （raw.githubusercontent.com → 失败自动切 cdn.jsdelivr.net，带超时）。
5. **逐个执行**：每个工具在独立子 shell 里跑，一个失败不影响下一个
   （`--fail-fast` 可改为立即停止）。
6. **汇总**：每个工具的成功/失败与耗时，最后给出退出码。

## 与上游的差异

| 上游 | 整合后的行为 |
|---|---|
| pi / omo / claude / codex | 原样调用其入口脚本，参数与体验完全一致 |
| GrokBuild | **有 `--base-url` / `--api-key` 时**由本脚本直接生成 `~/.grok/config.toml`（原子写入、`chmod 600`、自动备份、支持 `--dry-run`）；**没有凭据时**（或 `--delegate`）仍走上游的交互向导 |
| OpenCode | 本脚本内置实现（上游无对应仓库）：官方 installer 装 CLI + 合并写入 `opencode.json`，已有的 `plugin` / `mcp` / 其他 provider 全部保留 |

## 安全

- API Key 交互输入默认**不回显**，摘要里一律打码（`前4****后4`）。
- 生成的配置文件权限 `600`，写入前自动 `*.bak.<时间戳>` 备份。
- `--dry-run` 只打印计划，不写文件、不装软件。
- 上游脚本会以你的身份执行；`--pin` + `VERSIONS.md` 可以固定到已审阅的提交。

## 环境变量

`AICLI_BASE_URL` `AICLI_API_KEY` `AICLI_MODELS` `AICLI_MODEL` `AICLI_LANG`
`AICLI_REF` `AICLI_CACHE_DIR` `AICLI_RAW_HOST` `AICLI_OWNER`
`AICLI_OPENCODE_CONFIG` `AICLI_OPENCODE_PROVIDER` `AICLI_OPENCODE_METHOD`

## 兼容性

- macOS / Linux，bash 3.2+（无需 `brew install bash`）
- 需要 `curl` 或 `wget`；配置写入阶段需要 `node` 或 `bun`
  （claude 的 `--config-mode settings` 与 codex 的 TOML 校验额外需要 `python3`）
- Linux 上安装 Codex 需要 `root`/`sudo`

## CI

`.github/workflows/ci.yml` 在每次 push / PR 上跑：

- 所有自有脚本 `bash -n` + `shellcheck -S warning`（上游快照只做信息性检查）
- `CHANGELOG.md` 必须是最新的（跑 `./scripts/changelog.sh --all --update CHANGELOG.md` 后无 diff），
  并验证生成器幂等
- Ubuntu + macOS（含系统 bash 3.2）双平台冒烟测试
- `list` / `doctor` / `download` 离线快照解析
- 在隔离 `$HOME` 里真写一次 `opencode.json` 与 `~/.grok/config.toml`，
  校验内容、`600` 权限、备份文件，并验证 JSON 合并不丢已有键
- 验证 `--dry-run` 不落盘、`-y` 缺凭据会报错、未知工具被拒绝、管道模式可用

## 发布 / Release

`.github/workflows/release.yml` 在推送 `v*.*.*` tag 时触发：

```bash
git tag v1.0.0
git push origin v1.0.0
```

它会先跑一遍完整校验，再构建并上传这些产物到 GitHub Release：

| 产物 | 说明 |
|---|---|
| `ai-cli-setup.sh` | 统一入口脚本（单文件） |
| `changelog.sh` | CHANGELOG 生成器 |
| `SHA256SUMS` | 校验和 |
| `VERSION.txt` | 版本 / 提交 / 上游快照信息 |
| `CHANGELOG.md` `README.md` `LICENSE` | 随附文档 |

> Release 里的 `ai-cli-setup.sh` 可以单独使用：它在找不到本地 `upstream/`
> 快照时会自动从 GitHub 下载上游脚本（失败回退 jsDelivr）。
> 注意 GitHub 下载的 asset 不带可执行位，用前 `chmod +x`。

Release notes 自动从 `CHANGELOG.md` 摘出对应版本那一节。
也可在 Actions 页面手动 `workflow_dispatch` 只做构建校验（不发布）。

校验下载的产物：

```bash
# GitHub 下载的 asset 不带可执行位，先补上
chmod +x ai-cli-setup.sh changelog.sh
sha256sum -c SHA256SUMS
```

## CHANGELOG

`CHANGELOG.md` 由 `scripts/changelog.sh` 从 git 历史生成（约定式提交），
遵循 [Keep a Changelog](https://keepachangelog.com/)：

```bash
./scripts/changelog.sh                                    # 打印 [Unreleased]
./scripts/changelog.sh --all                              # 按 tag 重建整份
./scripts/changelog.sh --all --update CHANGELOG.md        # 写回文件（幂等）
./scripts/changelog.sh --version v1.1.0 --date 2026-01-01 --update CHANGELOG.md
./scripts/changelog.sh --no-links                         # 不生成提交链接
```

提交信息建议用 `feat:` / `fix:` / `perf:` / `refactor:` / `docs:` / `test:` /
`ci:` / `build:` / `chore:`，脚本会按类型分桶；不符合约定的归到 `Other`。

## 许可

本脚本 MIT。五个上游仓库均为 MIT，版权归各自作者（zxfccmm4）所有。
OpenCode（[opencode.ai](https://opencode.ai)）版权归其作者所有。
