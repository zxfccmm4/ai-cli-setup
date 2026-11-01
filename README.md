<div align="center">

# ⚡ ai-cli-setup

**一个脚本，装好并统一配置你所有的 AI CLI Agent**

选 Agent ➔ 官方渠道安装 ➔ 写入各家原生配置 · 凭据只问一次 · 国内网络自动加速

[![CI](https://img.shields.io/github/actions/workflow/status/zxfccmm4/ai-cli-setup/ci.yml?branch=main&label=CI&logo=github&style=flat-square)](https://github.com/zxfccmm4/ai-cli-setup/actions/workflows/ci.yml)
[![Release](https://img.shields.io/github/v/release/zxfccmm4/ai-cli-setup?label=Release&color=blue&style=flat-square)](https://github.com/zxfccmm4/ai-cli-setup/releases)
[![Bash](https://img.shields.io/badge/bash-3.2%2B-green.svg?style=flat-square&logo=gnu-bash)](https://www.gnu.org/software/bash/)
[![Platform](https://img.shields.io/badge/platform-Linux%20%7C%20macOS%20%7C%20musl-lightgrey.svg?style=flat-square)](https://github.com/zxfccmm4/ai-cli-setup)
[![License: MIT](https://img.shields.io/badge/license-MIT-blue.svg?style=flat-square)](LICENSE)

一条命令搞定 **Pi**、**OmO**、**OMP**、**Claude Code**、**Codex**、**Grok Build**、**OpenCode** 7 大主流 CLI Agent。<br />
各走官方渠道安装，原生配置自动生成，无第三方包装脚本，纯 Bash 实现。

</div>

---

## 目录

[一条命令开始](#-一条命令开始) · [核心特性](#-核心特性) · [支持的 Agent](#-支持的-agent) · [终端交互效果](#-终端交互效果) · [国内网络加速](#-国内网络加速) · [常用命令](#-常用命令) · [环境变量](#-环境变量) · [常见问题](#-常见问题) · [更多文档](#-更多文档) · [开源许可证](#-开源许可证)

---

## 🚀 一条命令开始

**中国大陆网络** —— 脚本本身走 CDN，安装走国内镜像：

```bash
curl -fsSL https://cdn.jsdelivr.net/gh/zxfccmm4/ai-cli-setup@main/ai-cli-setup.sh | bash -s -- --cn
```

**国际 / 可直连 GitHub**：

```bash
curl -fsSL https://raw.githubusercontent.com/zxfccmm4/ai-cli-setup/main/ai-cli-setup.sh | bash
```

> **为什么分两条？** 脚本内置的加速层在 bash 开始执行后才生效，而 `curl` 拉取脚本本身发生在更早一步。
> 国内直连 `raw.githubusercontent.com` 常被阻断，会卡在第一步、根本进不到加速逻辑 ——
> 所以大陆用户请用上面的 jsDelivr 版本（正规 CDN，非第三方反代）。

三种取得方式：

| 方式 | 命令 | 适合 |
| :--- | :--- | :--- |
| 一行命令 | 上面两条 `curl … \| bash` | 直接开装 |
| 克隆仓库 | `git clone https://github.com/zxfccmm4/ai-cli-setup.git` 后 `./ai-cli-setup.sh` | 想先读代码 |
| Release 产物 | `gh release download -R zxfccmm4/ai-cli-setup`，再 `chmod +x ai-cli-setup.sh` | 可复现 / 内网分发 |

运行后按提示走完即可：**选语言 → 选 Agent → 输入 Base URL 与 API Key → 自动安装并写入配置**。

---

## 🧩 环境要求

| 项 | 说明 |
| :--- | :--- |
| Shell | bash 3.2+（macOS 自带即可，**不需要** `brew install bash`） |
| 下载工具 | `curl` 或 `wget` |
| Node.js | **不要求预装**。缺失时脚本自己装：macOS 先试 Homebrew、Linux 先试 nodesource + apt，都不可用则免 root 装官方 tarball 到 `~/.local/share/pi-node/current`（带 sha256 校验） |
| `jq` / `node` / `python3` | 可选。用来更精确地解析模型列表、转义配置；一个都没有时有纯 Bash 兜底 |

| 环境 | 支持 | 说明 |
| :--- | :---: | :--- |
| **Linux (glibc)** | ✅ | Ubuntu、Debian、CentOS、Fedora、Arch 等全特性支持 |
| **macOS** | ✅ | 原生兼容；Claude Code 官方安装器仅支持 Linux/WSL，macOS 上只写配置不装 CLI |
| **中国大陆网络** | 🌏 | 自动识别并加速，见 [国内网络加速](#-国内网络加速) |
| **OpenWrt / Alpine（musl）** | ⚡ | 自动识别 musl 架构并安装官方 musl 构建；依赖 Node 的 Agent（Pi / OmO / OMP / Codex）标记为跳过但仍写配置，建议改在容器内运行 |

---

## ✨ 核心特性

| 特性 | 说明 |
| :--- | :--- |
| 🎯 **一键统管 7 个 Agent** | Pi、OmO、OMP、Claude Code、Codex、Grok Build、OpenCode，按需多选或全选安装 |
| 🌏 **国内网络自动加速** | npm、Node.js、GitHub 三个下载源**各自实测带宽后择优**，不盲目套镜像，详见[国内网络加速](#-国内网络加速) |
| 🔑 **凭据只问一次** | Base URL 与 API Key 统一采集，自动翻译成各家的原生配置格式（JSON / TOML / YAML）并批量写入 |
| 📡 **智能拉取模型** | 配置时请求网关的 `/v1/models` 端点，打印可用模型，一键全选或交互式挑几个 |
| 🧩 **合并写入，不丢配置** | OpenCode / Claude Code / OMP 均按键级、块级合并，已有插件、MCP、其它 Provider、`theme` 与 `modelRoles` 里的其它角色原样保留 |
| 🔒 **敏感信息防护** | API Key 实时掩码（`sk-******xyz`）；写出的配置文件强制 `600`；覆盖前生成带时间戳的备份；`--dry-run` 预览且零落盘 |
| 🛡 **反代下载校验** | 经 GitHub 反代下载的二进制按 GitHub 官方公布的 sha256 校验，不符即丢弃并改走其它渠道 |
| 🐧 **极致兼容** | glibc Linux、macOS（arm64 / x86_64）、musl 软路由均适配；无 `node` 的精简系统有纯 Bash 兜底 |

---

## 📦 支持的 Agent

| Agent | 官方安装渠道 | 配置文件 | 特别说明 |
| :--- | :--- | :--- | :--- |
| **Pi** | npm `@earendil-works/pi-coding-agent`（npm 不可用才回退 `pi.dev/install.sh`，并隔离其终端交互） | `~/.pi/agent/{models,settings}.json`<br />`JSON` | 自动配置 Provider 与默认模型；依赖 Node |
| **OmO** | `get.omo.dev`（回退 npm） | `~/.omo/agent/{models,settings}.json`<br />`JSON` | root 用户下自动授权执行；依赖 Node |
| **OMP** | `omp.sh/install`（回退 bun / npm） | `~/.omp/agent/{models.yml,config.yml}`<br />`YAML` | 保留 `modelRoles` 其它角色与主题设置；密钥强制 `600` |
| **Claude Code** | `claude.ai/install.sh`（回退 npm） | `${CLAUDE_CONFIG_DIR:-~/.claude}/settings.json`<br />`JSON` | 安装仅支持 Linux/WSL；macOS 仅写配置 |
| **Codex CLI** | npm `@openai/codex` | `~/.codex/{config.toml,auth.json}`<br />`TOML` / `JSON` | 自动写入模型映射与 Base URL；依赖 Node |
| **Grok Build** | `x.ai/cli/install.sh` | `~/.grok/config.toml`<br />`TOML` | 自动配置模型别名与上下文窗口 |
| **OpenCode** | `opencode.ai/install`（回退 GitHub Release → npm） | `${XDG_CONFIG_HOME:-~/.config}/opencode/opencode.json`<br />`JSON` | 自动识别 V1 / V2 规范并无损合并；安装器失败时直连 Release 兜底，且带 sha256 校验 |

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

## 🌏 国内网络加速

> 自 v2.2.0 起内置。国内直连 `nodejs.org`、`registry.npmjs.org`、GitHub Release 经常超时，
> 这套机制会自动绕开，**且不会把你本来很快的网络弄慢**。

### 三个下载源，各自测速择优

| 下载源 | 可选路径 | 判断方式 |
| :--- | :--- | :--- |
| npm registry | `registry.npmjs.org` ↔ `registry.npmmirror.com` | 各拉 1.5 MB tarball 比带宽，镜像快 20% 以上才切换 |
| Node.js 官方包 | `nodejs.org/dist` ↔ `npmmirror.com/mirrors/node` | 同上（官方源国内常约 19 B/s，镜像可达数 MB/s） |
| GitHub Release | 直连 ↔ GitHub 反代 | 先验证响应体是真二进制，再比带宽，反代快 50% 以上才切换 |

若检测到本地代理（Clash 等常见端口），直接全局走代理，优先级最高。

**反代下载有校验**：经 GitHub 反代拿到的二进制（如 OpenCode release）会按 GitHub API 公布的
sha256 校验，不符即丢弃并改走其它渠道；API 拿不到时只告警、不阻断。`--skip-install` 与
`--dry-run` 不会触发测速（反正不下载）。

### 第 0 步：脚本本身要先能下载下来

上面三个源都发生在 **bash 开始执行之后**。而 `curl ... | bash` 里的 `curl` 更早一步，
此时脚本还没运行、加速代码无从生效。所以大陆用户请用 jsDelivr 版本：

```bash
curl -fsSL https://cdn.jsdelivr.net/gh/zxfccmm4/ai-cli-setup@main/ai-cli-setup.sh | bash -s -- --cn
```

| 写法 | 适用 | 说明 |
| :--- | :--- | :--- |
| `cdn.jsdelivr.net/gh/<repo>@main/...` | 中国大陆 | CDN 缓存，国内可达；`@main` 跟随最新 |
| `cdn.jsdelivr.net/gh/<repo>@v2.3.0/...` | 需要可复现 | 锁定版本，CI 推荐 |
| `raw.githubusercontent.com/<repo>/main/...` | 国际 / 可直连 | 官方源，无中间层 |

> `bash -s -- --cn` 是把参数传给管道里的脚本；不加 `--cn` 时脚本也会自动判断国内网络，显式加上只是更稳妥。

> **为什么不无脑用镜像？**
> 国内镜像在境外出口上反而更慢（实测日本出口直连 GitHub 3.4 MB/s，反代仅 0.2 MB/s）。
> 无条件套镜像会让非大陆用户变慢，所以这里一律测速择优。

### 一条命令查看当前方案

```bash
./ai-cli-setup.sh cn
```

```text
ℹ  speed test npm: official 1377645B/s, mirror 5363563B/s
ℹ  speed test node: official 19B/s, mirror 4804354B/s
ℹ  speed test github: direct 1077687B/s, proxy 273372B/s
ℹ  plan: npm=https://registry.npmmirror.com/ node=https://npmmirror.com/mirrors/node github=direct

CN_MODE=1
PROXY=none
NPM_REGISTRY=https://registry.npmmirror.com/
NODE_MIRROR=https://npmmirror.com/mirrors/node
GH_PROXY=direct
```

### 开关与覆盖

```bash
# 强制开启（即使判断为非国内网络）
./ai-cli-setup.sh --cn all -y --base-url ... --api-key ...

# 强制关闭，全程官方源
./ai-cli-setup.sh --no-cn all -y --base-url ... --api-key ...

# 指定代理
./ai-cli-setup.sh --proxy http://127.0.0.1:7890 all
```

相关环境变量（`AICLI_CN`、`AICLI_PROXY`、`AICLI_GH_VERIFY` 等）见[环境变量](#-环境变量)。

**不会改动你的 `~/.npmrc`**：加速只通过本次进程的环境变量生效，脚本退出即失效。

### 实测收益

空缓存安装 `@openai/codex`：**53.7s → 7.9s（约 6.8 倍）**；Node.js 独立安装从「几乎不可用」变为可正常完成（含 sha256 校验）。

---

## 🛠 常用命令

```bash
# 引导式交互（首选，含语言选择）
./ai-cli-setup.sh

# 只装指定的几个
./ai-cli-setup.sh pi,opencode

# 完全非交互静默安装配置全部 Agent
./ai-cli-setup.sh all -y \
  --base-url https://gw.example.com/v1 \
  --api-key sk-xxxx \
  --models gpt-5.6,glm-5.3 \
  --model gpt-5.6

# 只重写配置，不碰已安装的 CLI
./ai-cli-setup.sh claude --skip-install

# 只预览执行计划，零落盘、零副作用
./ai-cli-setup.sh all --dry-run

# 环境与诊断
./ai-cli-setup.sh list      # 已装 Agent 及其路径
./ai-cli-setup.sh doctor    # 依赖命令、配置文件体检
./ai-cli-setup.sh cn        # 国内加速测速与最终方案
```

### 完整参数表

| 参数 | 说明 |
| :--- | :--- |
| `-y, --yes` | 非交互模式；缺凭据时在安装阶段之前就报错 |
| `-l, --lang en\|zh` | 界面语言（默认按系统 locale，跳过语言选择） |
| `--base-url URL` | 网关 API Base URL |
| `--api-key KEY` | 网关 API 密钥（交互输入时实时掩码） |
| `--models a,b,c` | 注册的模型 id 列表（pi / omo / omp / opencode） |
| `--model ID` | 默认模型 id（claude / codex / grok / omp / opencode） |
| `--grok-alias NAME` | Grok 本地模型别名（默认 `main`） |
| `--cn` / `--no-cn` | 强制开启 / 关闭国内加速（默认按网络自动判断） |
| `--proxy URL` | 给 curl 用的 HTTP 代理，如 `http://127.0.0.1:7890` |
| `--skip-install` | 只写配置，跳过二进制下载与安装 |
| `--dry-run` | 只打印计划，零落盘 |
| `--fail-fast` | 首个失败即停（默认失败隔离，继续装其它 Agent） |
| `--assume-tty` | 把 stdin 当交互输入（容器 / CI） |
| `-h, --help` / `-V, --version` | 帮助 / 版本 |

子命令：`list`、`doctor`、`cn`、`help`。位置参数可写 `pi`、`pi,opencode`、`all`。

---

## 🔧 环境变量

优先级：**命令行 > 环境变量 > 交互输入 > 默认值**。

### 凭据与模型

| 变量 | 作用 | 默认值 |
| :--- | :--- | :--- |
| `AICLI_BASE_URL` | 网关 API Base URL，如 `https://api.example.com/v1` | — |
| `AICLI_API_KEY` | 网关 API 密钥 | — |
| `AICLI_MODELS` | 注册的模型列表（逗号分隔） | 自动从端点拉取 |
| `AICLI_MODEL` | 默认模型 id | 模型列表首项 |

### 界面与交互

| 变量 | 作用 | 默认值 |
| :--- | :--- | :--- |
| `AICLI_LANG` | 界面语言 | `zh` / `en`（按系统 locale） |
| `AICLI_ASSUME_TTY` | 把标准输入视作终端（容器 / CI） | `0` / `1` |

### 国内网络加速

| 变量 | 作用 | 默认值 |
| :--- | :--- | :--- |
| `AICLI_CN` | 加速总开关 | `auto`（国内自动开启）/ `1` / `0` |
| `AICLI_PROXY` | 给 curl 用的代理 | 空（自动探测本地常见端口） |
| `AICLI_CN_BENCH` | 设为 `0` 跳过测速，直接使用国内镜像 | `1`（测速） |
| `AICLI_NPM_REGISTRY` | npm 镜像地址 | `https://registry.npmmirror.com/` |
| `AICLI_NODE_MIRROR` | Node.js 镜像地址 | `https://npmmirror.com/mirrors/node` |
| `AICLI_GH_PROXY` | GitHub 反代前缀 | `auto`（自动测速）/ 自填前缀 / `none` 强制直连 |
| `AICLI_GH_VERIFY` | 反代下载的二进制按官方 sha256 校验 | `1` / `0` 关闭 |
| `AICLI_GH_API` | GitHub API 地址（测试或私有代理用） | `https://api.github.com` |

### 各 Agent 专属

| 变量 | 作用 | 默认值 |
| :--- | :--- | :--- |
| `AICLI_OPENCODE_V2` | 强制采用 OpenCode V2 格式（使用 `{env:}` 凭据引用） | 自动探测 / `1` / `0` |
| `GROK_ALIAS` | Grok CLI 默认模型别名 | `main` |
| `GROK_CONTEXT_WINDOW` | Grok CLI 上下文窗口尺寸 | `500000` |
| `CODEX_WIRE_API` | Codex CLI 协议类型 | `responses` / `chat` |

---

## ❓ 常见问题

<details>
<summary><b>国内网络下脚本卡在下载 / 超时怎么办？</b></summary>
<br />

先跑 `./ai-cli-setup.sh cn` 看加速是否生效。如果判断为「未启用加速」（例如本机出口在境外），
可加 `--cn` 强制开启。若本地有 Clash 等代理，直接 `--proxy http://127.0.0.1:7890` 最省事。
</details>

<details>
<summary><b>为什么镜像没有生效，还是走的官方源？</b></summary>
<br />

这是**测速择优**的正常结果：只有当镜像比官方源快 20% 以上才会切换。
如果你的网络直连海外本来就很快（例如境外 VPS），走官方源就是最优解，脚本不会无谓地把你换到镜像。
想看具体数字请运行 `./ai-cli-setup.sh cn`，它会打印两边的实测带宽。
</details>

<details>
<summary><b>提示 <code>sha256 mismatch … discarding it</code> 是什么意思？</b></summary>
<br />

说明 GitHub 反代返回的内容与 GitHub 官方公布的 sha256 不一致（可能是反代缓存过期或被篡改），
脚本已丢弃该文件并改走其它渠道（通常是 npm）。可用 `AICLI_GH_PROXY=none` 强制直连 GitHub 重试。
</details>

<details>
<summary><b>输入 API Key 时界面好像卡住了？</b></summary>
<br />

这是正常的安全保护。输入密钥时终端启用掩码模式，只会显示 `sk-******xyz`，按键与粘贴均不回显明文，
输入完成后直接按回车即可。
</details>

<details>
<summary><b>Claude Code 界面正常，但对话时报错提示模型不存在？</b></summary>
<br />

当默认模型留空时，Claude Code 会尝试使用官方模型名（例如 `claude-opus-5-5`），部分第三方网关无法识别。
脚本**要求必须提供默认模型**（`--model`，或自动取 `--models` 的第一个）；若仍有问题，
请用 `--model <网关上的真实模型 ID>` 重新运行。
</details>

<details>
<summary><b>OMP 的密钥为什么是明文写在 <code>models.yml</code> 里？</b></summary>
<br />

这是 OMP 的限制：它的 `models.yml` **不做环境变量插值**（写 `${VAR}` 会被原样当成密钥发送），
也没有 OpenCode 那样的 `{env:}` 引用语法。脚本因此把密钥明文写入，并强制 `chmod 600` 保护该文件。
</details>

<details>
<summary><b>软路由（OpenWrt）上运行 OpenCode 报 <code>not found</code>？</b></summary>
<br />

musl 系统若误装了 glibc 预编译二进制，在动态链接器缺失时系统会报 `not found`。
本脚本内置 musl 架构识别并拉取官方 musl 构建。若命令仍无法直接调用，
请新开终端执行 `export PATH="$HOME/.opencode/bin:$PATH"`。
</details>

<details>
<summary><b>重复执行脚本会冲掉现有配置或插件吗？</b></summary>
<br />

不会。写入新配置前会自动生成时间戳备份（`*.bak.<timestamp>`）。对于 OpenCode、Claude Code 与 OMP，
脚本做键级 / 块级增量合并 —— 已有插件、MCP、其它 Provider、`theme`，以及 `modelRoles` 里的
`smol` / `slow` 等角色都不会丢失。
</details>

<details>
<summary><b>OpenCode V2 提示「当前终端先执行 source …」？</b></summary>
<br />

V2 格式把密钥放在 shell 环境变量里（`opencode.json` 只留 `{env:VAR}` 引用），写进 `.zshrc` /
`.bashrc` 只对**新开的 shell** 生效。按提示在当前终端载入一次（或直接新开一个终端）即可：

```bash
source ~/.zshrc          # bash 用户：source ~/.bashrc
```

想彻底避免这一步，可改用 V1 格式（密钥直写配置文件）：`AICLI_OPENCODE_V2=0 ./ai-cli-setup.sh opencode -y --skip-install …`
</details>

---

## 📚 更多文档

| 文档 | 内容 | 适合 |
| :--- | :--- | :--- |
| 📘 [快速上手 (Quick Start)](docs/quickstart.md) | 5 分钟装完第一个工具 | 第一次用 |
| ⚙️ [配置详解 (Configuration)](docs/configuration.md) | 每个 Agent 写什么文件、参数怎么映射 | 想搞清楚配置细节 |
| 🛠 [疑难排错 (Troubleshooting)](docs/troubleshooting.md) | 报错、网络、权限、备份回滚 | 出问题时 |
| 💻 [开发与发版 (Development)](docs/development.md) | 本地开发、测试、CI、发版规范 | 想改代码或发版 |
| 📝 [更新日志 (Changelog)](CHANGELOG.md) | 逐版本变更记录 | 看演进 |

---

## 📄 开源许可证

本项目基于 [MIT License](LICENSE) 开源。
