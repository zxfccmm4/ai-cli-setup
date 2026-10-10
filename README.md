<div align="center">

# ai-cli-setup

**一个脚本，装好你所有的 AI CLI agent**

English / 中文 · 凭据只问一次 · 一个失败不影响下一个

[![CI](https://github.com/zxfccmm4/ai-cli-setup/actions/workflows/ci.yml/badge.svg)](https://github.com/zxfccmm4/ai-cli-setup/actions/workflows/ci.yml)
[![Release](https://github.com/zxfccmm4/ai-cli-setup/actions/workflows/release.yml/badge.svg)](https://github.com/zxfccmm4/ai-cli-setup/actions/workflows/release.yml)
[![License: MIT](https://img.shields.io/badge/license-MIT-blue.svg)](LICENSE)

</div>

---

把 **zxfccmm4** 的 5 个 AI CLI 安装脚本（Pi / OmO / Claude Code / Codex / Grok Build）
加上 **OpenCode**，整合成**一个入口**。只做编排，不修改任何上游代码。

## 快速开始

```bash
curl -fsSL https://raw.githubusercontent.com/zxfccmm4/ai-cli-setup/main/ai-cli-setup.sh | bash
```

回答 3 个问题，其余全自动——真实输出长这样：

```text
$ curl -fsSL .../ai-cli-setup.sh | bash

Select language  /  选择语言          ① 选语言
  1) English
  2) 中文 (Chinese)
choose / 请选择 [1] 2

要配置哪些 AI agent？                ② 选 agent（单个 / 多个 / 全部）
  1) Pi           https://pi.dev
  2) OmO          https://omo.dev
  3) Claude Code  （仅 Linux/WSL）
  4) Codex CLI    https://github.com/openai/codex
  5) Grok Build   https://x.ai/cli
  6) OpenCode     https://opencode.ai
  7) 以上全部
  单个数字 = 单选   |   1,3 或 1-3 = 多选   |   a 或 7 = 全部
请选择 [7] 1,6
ℹ 已选择：Pi, OpenCode

接口 base URL: https://gw.example.com/v1   ③ 填一次凭据，所有 agent 共用
API key: sk-************xyz                （显式掩码：只显示前 3 + 后 3）
ℹ 发现 156 个模型：                        模型列表自动从网关拉取
  hdapi/gpt-5.6-sol
  hdapi/glm-5.3
  …（还有 153 个）
要写入的模型 id（逗号分隔，留空 = 全部）[hdapi/gpt-5.6-sol, … (+153 more)]

==> Pi — 开始        … 安装 + 写配置
==> OpenCode — 开始
汇总
  ✓ Pi       3s
  ✓ OpenCode 1s
```

| agent 菜单输入 | 含义 |
|---|---|
| `6` | 只装 OpenCode |
| `1,3` / `1 3` / `1-3` | 多选（逗号、空格、区间可混用） |
| `a` / `all` / `0` / `7` | 全部 |

无效输入最多重试 3 次。

## 支持的 agent

| agent | 来源 | 配置文件 | 备注 |
|---|---|---|---|
| `pi` | [pi-setup](https://github.com/zxfccmm4/pi-setup) · [pi.dev](https://pi.dev) | `~/.pi/agent/{models,settings}.json` | |
| `omo` | [omo-setup](https://github.com/zxfccmm4/omo-setup) · [omo.dev](https://omo.dev) | `~/.omo/agent/*`、`~/.omo/omo.jsonc` | |
| `claude` | [claude-code-linux-installer](https://github.com/zxfccmm4/claude-code-linux-installer) | shell 配置或 `~/.claude/settings.json` | **仅 Linux / WSL** |
| `codex` | [deploy-codex](https://github.com/zxfccmm4/deploy-codex) | `~/.codex/{config.toml,auth.json}` | Linux 安装需 root |
| `grok` | [GrokBuild](https://github.com/zxfccmm4/GrokBuild) | `~/.grok/config.toml` | |
| `opencode` | 本脚本内置实现 | `~/.config/opencode/opencode.json` | 无上游仓库 |

`opencode`：官方 installer（`https://opencode.ai/install`）装 CLI，失败回退 `npm i -g opencode-ai`，
然后**合并**写入 `opencode.json`（已有的 `plugin` / `mcp` / 其他 provider 全部保留）。

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
  --models gpt-5.6,gpt-5.5,claude-sonnet-5-5
```

- `-y` 非交互模式下缺 `--base-url` / `--api-key` 直接报错
- 模型列表自动请求 `<base_url>/v1/models`（带 Bearer 鉴权）；拉不到再手输 `--models`
- 更多选项（`--grok-search on`、`--opencode-method npm`、`--pin` 等）见 `--help`

### 常用辅助命令

```bash
./ai-cli-setup.sh doctor          # 环境体检：依赖、已装 CLI、配置文件
./ai-cli-setup.sh list            # 工具清单 + 上游版本 + 缓存状态
./ai-cli-setup.sh download all    # 预下载全部上游脚本（离线可用）
./ai-cli-setup.sh all --dry-run   # 只打印计划，不落盘、不安装
./ai-cli-setup.sh codex -- --restore   # "--" 之后原样透传给上游脚本
```

## 工作原理

1. **选语言** → **选 agent** → **问一次凭据**（base_url + api_key，自动拉模型）。
2. **翻译凭据**：统一参数映射为各上游认识的环境变量 / 配置——

   | 统一参数 | pi | omo | claude | codex | grok | opencode |
   |---|---|---|---|---|---|---|
   | `--base-url` | `PISETUP_BASE_URL` | `OMO_BASE_URL` | `CLAUDE_BASE_URL` | `CODEX_BASE_URL` | 写入 config.toml | `provider.options.baseURL` |
   | `--api-key` | `PISETUP_API_KEY` | `OMO_API_KEY` | `CLAUDE_API_KEY` | `CODEX_API_KEY` | 写入 config.toml | `provider.options.apiKey` |
   | `--models` | `PISETUP_MODELS` | `OMO_MODELS` | — | — | — | `provider.models` + `model` |

3. **取上游脚本**：优先仓库内 `upstream/<repo>/` 快照（离线可用）；否则下载到
   `~/.cache/ai-cli-setup/`（GitHub raw 失败自动切 jsDelivr）。
4. **逐个执行**：独立子 shell，一个失败不影响下一个（`--fail-fast` 改为立即停止）。
5. **汇总**：成功 / 失败 + 耗时。

## 安全

- API key **显式掩码输入**：实时显示 `前3 + 星号 + 后3`（如 `sk-************xyz`），
  支持退格 / Ctrl-U 清空；粘贴不会闪现明文；日志打码同规则。
- 写入的配置权限 `600`，写入前自动 `*.bak.<时间戳>` 备份。
- `--dry-run` 只打印计划，不写文件、不装软件。
- `--pin` + [VERSIONS.md](VERSIONS.md) 可把上游固定到已验证提交。

## 常见问题

<details>
<summary><b>看起来卡住了？</b></summary>

大概率是在等你回答问题。三个必答项：语言、agent 选择、凭据。API key 输入时只显示掩码
（`sk-***xyz`），你敲的字符不会原样出现——输完回车即可。模型列表那一步留空回车 = 全部注册。
</details>

<details>
<summary><b>curl | bash 没出现菜单？</b></summary>

v1.0.0 有一个 stderr 被吞的 bug（菜单全走 stderr），v1.1.0 已修复。确认跑的是最新版：
`curl -fsSL .../ai-cli-setup.sh | bash`（注意 URL 是 `main` 分支）。容器 / CI 里没有
`/dev/tty` 时，加 `--assume-tty` 把 stdin 当交互输入。
</details>

<details>
<summary><b>模型列表拉不到？</b></summary>

脚本会带 API key 请求 `<base_url>/v1/models`。失败原因通常是：key 无效、base_url 不带
`/v1`、或网关不支持该接口。拉不到时直接手输模型 id（逗号分隔）即可，如
`hdapi/gpt-5.6-sol,hdapi/glm-5.3`。
</details>

<details>
<summary><b>只改配置、不重装 CLI？</b></summary>

`./ai-cli-setup.sh <agent> --skip-install -y --base-url ... --api-key ...`——只写配置文件，
不安装 / 更新二进制。
</details>

<details>
<summary><b>装完 Pi / OmO 报「No models available」？</b></summary>

配置没写成功。多半是凭据在管道模式下没传进去（旧版 bug，v1.1.0 已修复）。重跑一次；
确认 `~/.pi/agent/models.json` 里 `apiKey` 与 `baseUrl` 都在。
</details>

## 兼容性 / 依赖

- macOS / Linux，bash 3.2+（无需 `brew install bash`）。
- `curl` 或 `wget` 必需；opencode 配置写入需要 `node`；TOML / JSON 校验需要 `python3`。
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

CI（[ci.yml](.github/workflows/ci.yml)）每次 push / PR 跑：双平台（Ubuntu / macOS 含 bash 3.2）
语法 + shellcheck、交互流程测试（语言 / agent 选择 / 重试 / 掩码）、隔离 HOME 真写配置并校验
内容与权限、`--dry-run` 不落盘、管道模式可用。

推送 tag 触发 Release（[release.yml](.github/workflows/release.yml)）：

```bash
git tag v1.1.0 && git push origin v1.1.0
```

产物：`ai-cli-setup.sh`、`changelog.sh`、`SHA256SUMS`、`VERSION.txt` 及文档。
Release 里下载的 asset 不带可执行位：`chmod +x ai-cli-setup.sh && sha256sum -c SHA256SUMS`。

## CHANGELOG

`CHANGELOG.md` 由 [scripts/changelog.sh](scripts/changelog.sh) 从 git 历史生成（约定式提交），
遵循 [Keep a Changelog](https://keepachangelog.com/)：

```bash
./scripts/changelog.sh                                    # 打印 [Unreleased]
./scripts/changelog.sh --all --update CHANGELOG.md        # 按 tag 重建并写回（幂等）
```

## 许可

MIT。五个上游仓库均为 MIT，版权归各自作者所有。OpenCode 版权归其作者所有。
