#!/usr/bin/env bash
#
# ai-cli-setup.sh — 一键安装并配置你的 AI CLI agent（全自研，无上游依赖）
#
# 流程：
#   1) 选语言（English / 中文）
#   2) 选 agent（单个 / 多个 / 全部）
#   3) 依次安装所选 agent（官方渠道：原生 installer / npm）
#   4) 统一收集凭据（base_url + api_key，带掩码输入）+ 拉取模型列表
#   5) 批量写入每个 agent 的配置文件
#   6) 汇总报告
#
# 用法：
#   ./ai-cli-setup.sh                                   # 交互：语言 → agent → 安装 → 配置
#   ./ai-cli-setup.sh pi,opencode                       # 直接指定 agent
#   ./ai-cli-setup.sh all -y --base-url URL --api-key KEY --models a,b
#   ./ai-cli-setup.sh list | doctor | help
#
# 环境变量见 --help。
#
set -Eeuo pipefail

VERSION="2.2.0"
NAME="ai-cli-setup"

# ============================================================
# 0. bash 兼容
# ============================================================
if [ -z "${BASH_VERSION:-}" ]; then exec bash "$0" "$@"; fi

# ============================================================
# 1. 全局状态
# ============================================================
LANG_CODE="${AICLI_LANG:-}"
LANG_EXPLICIT=0
[ -n "$LANG_CODE" ] && LANG_EXPLICIT=1

NON_INTERACTIVE=0
SKIP_INSTALL=0
DRY_RUN=0
FAIL_FAST=0
ASSUME_TTY=0
case "$(printf '%s' "${AICLI_ASSUME_TTY:-0}" | tr 'A-Z' 'a-z')" in
  1|true|yes|on) ASSUME_TTY=1 ;;
esac

BASE_URL="${AICLI_BASE_URL:-}"
API_KEY="${AICLI_API_KEY:-}"
MODELS="${AICLI_MODELS:-}"
MODEL="${AICLI_MODEL:-}"          # 默认模型（claude/codex/grok/opencode）

SELECTED=""                       # 逗号分隔的 agent id

# ============================================================
# 2. i18n
# ============================================================
normalize_lang() {
  case "$1" in
    zh|zh-*|zh_*|*[_-]CN*|*[_-]TW*|*[_-]HK*) printf 'zh' ;;
    *) printf 'en' ;;
  esac
}
if [ -n "$LANG_CODE" ]; then LANG_CODE="$(normalize_lang "$LANG_CODE")"
else LANG_CODE="$(normalize_lang "${LC_ALL:-${LC_MESSAGES:-${LANG:-}}}")"; fi

lc() { if [ "$LANG_CODE" = "zh" ]; then printf '%s' "$2"; else printf '%s' "$1"; fi; }

# ============================================================
# 3. 输出
# ============================================================
if [ -t 1 ] || [ -t 2 ]; then
  BOLD=$'\033[1m'; DIM=$'\033[2m'; RED=$'\033[31m'; GREEN=$'\033[32m'
  YELLOW=$'\033[33m'; CYAN=$'\033[36m'; MAGENTA=$'\033[35m'; RESET=$'\033[0m'
else
  BOLD=; DIM=; RED=; GREEN=; YELLOW=; CYAN=; MAGENTA=; RESET=
fi
info() { printf '%s\n' "${CYAN}ℹ${RESET}  $*" >&2; }
ok()   { printf '%s\n' "${GREEN}✓${RESET}  $*" >&2; }
warn() { printf '%s\n' "${YELLOW}!${RESET}  $*" >&2; }
err()  { printf '%s\n' "${RED}✗${RESET}  $*" >&2; }
step() { printf '\n%s\n' "${BOLD}${MAGENTA}==>${RESET} ${BOLD}$*${RESET}" >&2; }
die()  { err "$*"; exit 1; }

# ============================================================
# 4. TTY / 输入
# ============================================================
stdin_is_input() { [ -t 0 ] || [ "$ASSUME_TTY" -eq 1 ]; }
interactive_run() { [ "$NON_INTERACTIVE" -eq 0 ] && { stdin_is_input || { exec 9<>/dev/tty; } 2>/dev/null; }; }

# read_line <var> <prompt>            普通行输入
# read_line <var> <prompt> 1          密钥输入：实时掩码（前3+星+后3），支持退格/Ctrl-U
# READ_EOF=1 表示上次 read_line 遇到 stdin EOF（输入耗尽）
READ_EOF=0
read_line() {
  local __var="$1" __prompt="$2" __secret="${3:-0}"
  READ_EOF=0
  if [ "$__secret" = "1" ]; then read_secret "$__var" "$__prompt"; return; fi
  local __ans=""
  if stdin_is_input; then
    printf '%s' "$__prompt" >&2
    IFS= read -r __ans || READ_EOF=1
  elif { exec 9<>/dev/tty; } 2>/dev/null; then
    printf '%s' "$__prompt" > /dev/tty
    IFS= read -r __ans < /dev/tty || READ_EOF=1
    exec 9>&- 9<&-
  else
    printf '%s' "$__prompt" >&2
    IFS= read -r __ans || READ_EOF=1
  fi
  printf -v "$__var" '%s' "$__ans"
}

repeat_char() {
  local ch="$1" n="${2:-0}"
  [ "$n" -gt 0 ] || return 0
  local s=""
  printf -v s '%*s' "$n" ''
  printf '%s' "${s// /$ch}"
}

secret_mask() {
  local s="${1:-}"
  local len="${#s}"
  if [ -z "$s" ] || [ "$len" -le 6 ]; then
    repeat_char '*' "$len"
  else
    local mid=$((len - 6))
    printf '%s%s%s' "${s:0:3}" "$(repeat_char '*' "$mid")" "${s: -3}"
  fi
}

# 掩码回显输出。必须用 fd 复制（>&2）而不是 `> /dev/stderr`：
# 在 Linux 上 /dev/stderr 是 /proc/self/fd/2 的符号链接，用 `>` 打开会
# 以 O_TRUNC 重新打开它指向的文件，把调用方重定向的日志截断，
# 并从偏移 0 重新写入（与 shell 自己的 fd 2 偏移错位，中间留下 NUL 空洞）。
# 结果就是 `script > out 2>&1` 时 out 前半段丢失、出现 \0 填充。
secret_echo() {  # secret_echo <text> <tty|stderr>
  if [ "$2" = "stderr" ]; then
    printf '%s' "$1" >&2
  else
    printf '%s' "$1" > /dev/tty 2>/dev/null || printf '%s' "$1" >&2
  fi
  return 0
}

read_secret() {
  local __var="$1" __prompt="$2" __c="" __buf="" __prev=0 __m=""
  local __in="/dev/tty" __mode="tty"
  stdin_is_input && { __in="/dev/stdin"; __mode="stderr"; }
  secret_echo "$__prompt" "$__mode"

  if [ "$__in" = "/dev/stdin" ] && [ ! -t 0 ]; then
    IFS= read -r __buf || true
    printf '%s\n' "$(secret_mask "$__buf")" >&2
    printf -v "$__var" '%s' "$__buf"; return 0
  fi

  local __saved=""
  __saved="$(stty -g < "$__in" 2>/dev/null || true)"
  [ -n "$__saved" ] && { stty -echo < "$__in" 2>/dev/null || true; trap 'stty echo 2>/dev/null || true' INT TERM HUP; }

  while :; do
    local __c=""
    if [ "$__in" = "/dev/stdin" ]; then IFS= read -r -n 1 __c || break
    else IFS= read -r -n 1 __c < "$__in" || break; fi
    [ -z "$__c" ] && break
    case "$__c" in
      $'\x7f'|$'\x08')
        if [ -n "$__buf" ]; then
          __buf="${__buf%?}"; __m="$(secret_mask "$__buf")"
          [ "$__prev" -gt 0 ] && secret_echo "$(repeat_char $'\b' "$__prev")" "$__mode"
          secret_echo "$__m" "$__mode"
          local __pad=$((__prev - ${#__m}))
          if [ "$__pad" -gt 0 ]; then
            secret_echo "$(printf '%*s' "$__pad" '')" "$__mode"
            secret_echo "$(repeat_char $'\b' "$__pad")" "$__mode"
          fi
          __prev=${#__m}
        fi ;;
      $'\x15')
        if [ "$__prev" -gt 0 ]; then
          secret_echo "$(repeat_char $'\b' "$__prev")" "$__mode"
          secret_echo "$(printf '%*s' "$__prev" '')" "$__mode"
          secret_echo "$(repeat_char $'\b' "$__prev")" "$__mode"
        fi
        __buf=""; __prev=0 ;;
      $'\x04') break ;;
      *)
        __buf="${__buf}${__c}"; __m="$(secret_mask "$__buf")"
        [ "$__prev" -gt 0 ] && secret_echo "$(repeat_char $'\b' "$__prev")" "$__mode"
        secret_echo "$__m" "$__mode"
        __prev=${#__m} ;;
    esac
  done
  [ -n "$__saved" ] && { stty "$__saved" < "$__in" 2>/dev/null || true; trap - INT TERM HUP; }
  secret_echo $'\n' "$__mode"
  printf -v "$__var" '%s' "$__buf"
  return 0
}

confirm() {
  local __p="${1:-}" __def="${2:-n}" __ans=""
  [ "$NON_INTERACTIVE" -eq 1 ] && return 0
  if [ "$__def" = "y" ]; then
    read_line __ans "$__p ${DIM}[Y/n]${RESET} "
    case "$__ans" in ""|[yY]|[yY][eE][sS]) return 0 ;; *) return 1 ;; esac
  fi
  read_line __ans "$__p ${DIM}[y/N]${RESET} "
  case "$__ans" in [yY]|[yY][eE][sS]) return 0 ;; *) return 1 ;; esac
}

# ============================================================
# 5. 平台
# ============================================================
OS=""; ARCH=""
case "$(uname -s)" in
  Darwin) OS=macos ;; Linux) OS=linux ;; *) OS="$(uname -s | tr 'A-Z' 'a-z')" ;;
esac
case "$(uname -m)" in
  x86_64|amd64) ARCH=x86_64 ;; arm64|aarch64) ARCH=arm64 ;; *) ARCH="$(uname -m)" ;;
esac
is_root() { [ "$(id -u)" -eq 0 ]; }

have() { command -v "$1" >/dev/null 2>&1; }

detect_shellrc() {
  case "${SHELL:-}" in
    *zsh*) [ -f "$HOME/.zshrc" ] && { printf '%s' "$HOME/.zshrc"; return 0; } ;;
    *bash*) [ -f "$HOME/.bashrc" ] && { printf '%s' "$HOME/.bashrc"; return 0; } ;;
  esac
  if [ -f "$HOME/.zshrc" ] && [ ! -f "$HOME/.bashrc" ]; then
    printf '%s' "$HOME/.zshrc"
  elif [ -f "$HOME/.bashrc" ]; then
    printf '%s' "$HOME/.bashrc"
  elif [ -f "$HOME/.zshrc" ]; then
    printf '%s' "$HOME/.zshrc"
  else
    printf '%s' "$HOME/.bashrc"
  fi
}

# ============================================================
# 6. agent 清单
# ============================================================
ALL_AGENTS="pi omo omp claude codex grok opencode"

agent_valid() { case "$1" in pi|omo|omp|claude|codex|grok|opencode) return 0 ;; *) return 1 ;; esac; }
agent_title() {
  case "$1" in
    pi) printf 'Pi' ;; omo) printf 'OmO' ;; omp) printf 'OMP' ;; claude) printf 'Claude Code' ;;
    codex) printf 'Codex CLI' ;; grok) printf 'Grok Build' ;; opencode) printf 'OpenCode' ;;
  esac
}
agent_homepage() {
  case "$1" in
    pi) printf 'https://pi.dev' ;; omo) printf 'https://omo.dev' ;;
    omp) printf 'https://omp.sh' ;;
    claude) printf 'https://claude.com/product/claude-code' ;;
    codex) printf 'https://github.com/openai/codex' ;;
    grok) printf 'https://x.ai/cli' ;; opencode) printf 'https://opencode.ai' ;;
  esac
}
# 安装命令（官方渠道）
agent_bin() {
  case "$1" in
    pi) printf 'pi' ;; omo) printf 'omo' ;; omp) printf 'omp' ;; claude) printf 'claude' ;;
    codex) printf 'codex' ;; grok) printf 'grok' ;; opencode) printf 'opencode' ;;
  esac
}
# 该 agent 是否只在 Linux 安装
agent_linux_only() { case "$1" in claude) return 0 ;; *) return 1 ;; esac; }
# 配置是否需要模型列表（多模型注册）
agent_needs_models() { case "$1" in pi|omo|omp|opencode) return 0 ;; *) return 1 ;; esac; }
# 配置是否需要单个默认模型
agent_needs_model() { case "$1" in claude|codex|grok|omp|opencode) return 0 ;; *) return 1 ;; esac; }

# 该 agent 在当前系统上是否根本装不了/跑不起来（用于“优雅跳过”而不是失败）。
# musl 软路由（OpenWrt/iStoreOS）无法直接运行 Node.js：pi/omo/omp/codex 都依赖它。
# 返回 0 = 跑不了（应 SKIP）；返回 1 = 可以尝试安装。
agent_unrunnable_here() {
  local a="$1"
  [ "$OS" = "linux" ] || return 1
  is_musl_system || return 1
  have node && return 1          # 用户可能已自行装了 musl 版 node，尊重之
  case "$a" in
    # omp 有官方预编译二进制、也可走 bun（不依赖 node），交给安装步骤自己判断
    omp) have bun && return 1; return 0 ;;
    pi|omo|codex) return 0 ;;
    *) return 1 ;;
  esac
}

# ============================================================
# 6.5 中国大陆加速
# ============================================================
# 三个下载来源各自决定，全部按“实测下载速度”择优，而不是无条件走镜像：
#   npm registry  -> registry.npmjs.org  或 registry.npmmirror.com（淘宝源）
#   Node.js 官方包 -> nodejs.org         或 npmmirror.com/mirrors/node
#   github.com    -> 直连 或 GitHub 反代（gh-proxy.com / ghproxy.net …）
# 实测参考（国内网络）：npm 安装 @openai/codex 从 53.7s 降到 7.9s；
# nodejs.org 在国内基本连不上（约 19 B/s），镜像约 20 MB/s；GitHub release 直连常被墙。
# 关键教训：只判断“能不能连上”不可靠 —— ghproxy.cn 会返回 HTML 验证页，
# 用 -r 0-0 探测会误判为成功。必须校验响应体是不是真的二进制，并比较速度，
# 否则会把本来很快的直连换成慢镜像（实测日本出口直连 GitHub 3.4MB/s > 反代 0.2MB/s）。
# 环境变量：
#   AICLI_CN=auto|1|0     auto（默认）：国内网络启用加速
#   AICLI_PROXY=...       给 curl 用的代理，如 http://127.0.0.1:7890
#   AICLI_CN_BENCH=0      跳过测速，直接用国内镜像
#   AICLI_GH_PROXY=URL    GitHub 反代前缀；"auto" 测速，"none" 强制直连
#   AICLI_NPM_REGISTRY=URL
#   AICLI_NODE_MIRROR=URL
CN_MODE=0
PROXY="${AICLI_PROXY:-}"
NPM_REGISTRY="${AICLI_NPM_REGISTRY:-https://registry.npmmirror.com/}"
NPM_REGISTRY_OFFICIAL="https://registry.npmjs.org/"
NODE_MIRROR="${AICLI_NODE_MIRROR:-https://npmmirror.com/mirrors/node}"
NODE_MIRROR_OFFICIAL="https://nodejs.org/dist"
GH_PROXY=""
# 存放 dist 的目录前缀：nodejs.org/dist/latest-v22.x/... 与
# npmmirror.com/mirrors/node/latest-v22.x/... 布局不同，只能各记各的，不能拼接。
NODE_DIST_OFFICIAL="https://nodejs.org/dist"
NODE_DIST_MIRROR="${NODE_MIRROR%/}"
NODE_DIST=""
# 实测能返回真实二进制的 GitHub 反代（ghproxy.cn 会返回 HTML 验证页，已排除）
GH_PROXY_CANDIDATES="https://gh-proxy.com/ https://ghproxy.net/ https://ghfast.top/"

is_cn_network() {
  local tz="" cc=""
  tz="$(readlink /etc/localtime 2>/dev/null || true)"
  case "$tz" in *Asia/Shanghai*|*Asia/Chongqing*|*Asia/Urumqi*|*Asia/Harbin*|*PRC*) return 0 ;; esac
  if [ -n "${TZ:-}" ]; then
    case "$TZ" in Asia/Shanghai|Asia/Chongqing|Asia/Urumqi|Asia/Harbin|PRC) return 0 ;; esac
  fi
  have curl || return 1
  # 出口 IP 归属地：国内为 loc=CN，日本/新加坡等为 loc=JP/…
  cc="$(curl -fsS --connect-timeout 2 --max-time 4 https://www.cloudflare.com/cdn-cgi/trace 2>/dev/null \
        | awk -F= '$1=="loc"{print $2}' || true)"
  case "$cc" in CN|HK|MO) return 0 ;; esac
  return 1
}

# probe_speed <url> [rounds] -> 输出字节/秒
# 单次采样波动很大（同一 URL 实测 0.15~10MB/s），所以取多轮最大值。
# 用 1.5MB 的 Range 只估带宽，外加 --speed-limit 早停，不把文件下完。
probe_speed() {
  local url="$1" rounds="${2:-2}" i best=0 out sp
  for i in $(seq 1 "$rounds"); do
    out="$(curl -sSL --connect-timeout 4 --max-time 10 --range 0-1500000 \
            --speed-limit 1 --speed-time 5 -o /dev/null \
            -w '%{http_code} %{size_download} %{speed_download}' "$url" 2>/dev/null || true)"
    sp="$(printf '%s' "$out" | awk '$1==200||$1==206{ if ($2>50000) print int($3); else print 0 }')"
    sp="${sp:-0}"
    [ "$sp" -gt "$best" ] && best="$sp"
  done
  printf '%s' "$best"
}

# pick_faster <official_url> <mirror_url> <label> <probe_file>
# probe_file：用来测速的实际大文件（npm 元数据只有几十 KB，测不出带宽）。
pick_faster() {
  local off="$1" mir="$2" label="$3" file="$4" so sm
  if [ "${AICLI_CN_BENCH:-1}" = "0" ]; then printf '%s' "$mir"; return 0; fi
  so="$(probe_speed "${off%/}/${file}")"
  sm="$(probe_speed "${mir%/}/${file}")"
  info "$(lc "speed test $label: official ${so}B/s, mirror ${sm}B/s" "测速 $label 官方 ${so}B/s ，镜像 ${sm}B/s")"
  if [ "$sm" -gt 0 ] && [ "$((sm * 10))" -gt "$((so * 12))" ]; then
    printf '%s' "$mir"
  else
    printf '%s' "$off"
  fi
}

# pick_gh_proxy -> 输出一个确实能返回二进制内容的反代前缀，没有则输出空
pick_gh_proxy() {
  local p out sig sz probe
  probe="/tmp/.aicli-ghprobe.$$"
  for p in $GH_PROXY_CANDIDATES; do
    rm -f "$probe"
    out="$(curl -sSL --connect-timeout 4 --max-time 12 --range 0-63 -o "$probe" \
            -w '%{http_code}' "${p}https://github.com/anomalyco/opencode/releases/latest/download/opencode-darwin-arm64.zip" 2>/dev/null || true)"
    if [ -f "$probe" ]; then
      sig="$(head -c 2 "$probe" 2>/dev/null | od -An -tx1 | tr -d ' \n')"
      sz="$(wc -c < "$probe" 2>/dev/null | tr -d ' ')"
      rm -f "$probe"
    else
      sig=""; sz=0
    fi
    case "$out" in 200|206) ;; *) continue ;; esac
    [ "${sz:-0}" -ge 16 ] || continue
    # 真二进制不会以 "<!" 开头（HTML 验证页）
    [ "$sig" = "3c21" ] && continue
    printf '%s' "$p"; return 0
  done
  printf ''
}

# 把 github.com / raw.githubusercontent.com 的 URL 套上选中的反代；其它原样返回
gh_mirror_url() {
  local url="$1"
  case "$url" in *github.com/*|*raw.githubusercontent.com/*) ;; *) printf '%s' "$url"; return 0 ;; esac
  if [ -n "$GH_PROXY" ]; then printf '%s%s' "${GH_PROXY%/}/" "$url"; else printf '%s' "$url"; fi
}

cn_init() {
  case "$(printf '%s' "${AICLI_CN:-auto}" | tr 'A-Z' 'a-z')" in
    1|true|yes|on)  CN_MODE=1 ;;
    0|false|no|off) CN_MODE=0 ;;
    *) if is_cn_network; then CN_MODE=1; fi ;;
  esac

  if [ "$CN_MODE" != "1" ]; then
    info "$(lc 'acceleration off; official sources only' '未启用加速，只使用官方源')"
    return 0
  fi

  # 1) 本地代理（Clash 等）：有就全局走代理，最省事
  if [ -z "$PROXY" ]; then
    local cand
    for cand in http://127.0.0.1:7890 http://127.0.0.1:7897 http://127.0.0.1:10809 http://127.0.0.1:1080; do
      if curl -fsS --connect-timeout 1 --max-time 2 --noproxy '' -x "$cand" -o /dev/null https://registry.npmjs.org/ 2>/dev/null; then
        PROXY="$cand"; break
      fi
    done
  fi
  if [ -n "$PROXY" ]; then
    export http_proxy="$PROXY" https_proxy="$PROXY" HTTP_PROXY="$PROXY" HTTPS_PROXY="$PROXY"
    info "$(lc "detected local proxy $PROXY (all downloads via proxy)" "检测到本地代理 $PROXY ，全部下载走代理")"
    return 0
  fi

  # 2) npm：官方 vs 淘宝源
  # tarball 是 npm 装包的真实流量来源，用它测更有代表性
  NPM_CONFIG_REGISTRY="$(pick_faster "$NPM_REGISTRY_OFFICIAL" "$NPM_REGISTRY" "npm" "@openai/codex/-/codex-0.50.0.tgz")"
  export NPM_CONFIG_REGISTRY

  # 3) Node.js 包
  local node_pick
  node_pick="$(pick_faster "$NODE_MIRROR_OFFICIAL" "$NODE_MIRROR" "node" "latest-v22.x/node-v22.20.0-darwin-arm64.tar.gz")"
  if [ "$node_pick" = "$NODE_MIRROR" ]; then NODE_DIST="$NODE_DIST_MIRROR"; else NODE_DIST="$NODE_DIST_OFFICIAL"; fi

  # 4) GitHub：直连 vs 反代（用户显式指定时跳过测速）
  case "${AICLI_GH_PROXY:-auto}" in
    none|"") GH_PROXY="" ;;
    auto)    auto_gh=1 ;;
    *)       GH_PROXY="$AICLI_GH_PROXY"; auto_gh=0 ;;
  esac
  if [ "${auto_gh:-1}" = "1" ] && [ "${AICLI_CN_BENCH:-1}" != "0" ]; then
    local gp ghc d s
    ghc="https://github.com/anomalyco/opencode/releases/latest/download/opencode-darwin-arm64.zip"
    gp="$(pick_gh_proxy)"
    if [ -n "$gp" ]; then
      d="$(probe_speed "$ghc" 8)"; s="$(probe_speed "${gp}${ghc}" 8)"
      d="${d:-0}"; s="${s:-0}"
      info "$(lc "speed test github: direct ${d}B/s, proxy ${s}B/s" "测速 GitHub：直连 ${d}B/s ，反代 ${s}B/s")"
      if [ "$s" -gt 0 ] && [ "$((s * 10))" -gt "$((d * 15))" ]; then GH_PROXY="$gp"; fi
    fi
  fi

  info "$(lc "plan: npm=$NPM_CONFIG_REGISTRY node=$NODE_DIST github=${GH_PROXY:-direct}" "加速方案：npm = $NPM_CONFIG_REGISTRY ，Node = $NODE_DIST ，GitHub = ${GH_PROXY:-直连}")"
}

# cn_selftest_out：`ai-cli-setup cn` 的输出，用来确认加速方案
cn_selftest_out() {
  printf 'CN_MODE=%s\nPROXY=%s\nNPM_REGISTRY=%s\nNODE_MIRROR=%s\nGH_PROXY=%s\n' \
    "$CN_MODE" "${PROXY:-none}" "${NPM_CONFIG_REGISTRY:-official}" \
    "${NODE_DIST:-$NODE_DIST_MIRROR}" "${GH_PROXY:-direct}"
}

# GitHub release 直链原始 URL（未套反代）
opencode_release_url() {
  local arch="x64"
  case "$(uname -m)" in aarch64|arm64) arch="arm64" ;; esac
  case "$OS" in
    macos) if [ "$ARCH" = "arm64" ]; then printf '%s' "https://github.com/anomalyco/opencode/releases/latest/download/opencode-darwin-arm64.zip";
           else printf '%s' "https://github.com/anomalyco/opencode/releases/latest/download/opencode-darwin-x64.zip"; fi ;;
    *) printf '%s' "https://github.com/anomalyco/opencode/releases/latest/download/opencode-linux-${arch}-musl.tar.gz" ;;
  esac
}

# ============================================================
# 7. 安装（全自研：官方 installer / npm，不依赖 zxfccmm4 仓库）
# ============================================================
# 依赖缺失一律“返回失败”而不是 die：单个 agent 失败不应中断其它 agent
# （--fail-fast 由调用方统一处理）。
need_dl() {
  have curl && return 0
  have wget && return 0
  err "$(lc 'need curl or wget' '需要 curl 或 wget')"
  return 1
}

run_official() {  # run_official <url> [args...]
  local url="$1"; shift
  need_dl || return 1
  url="$(gh_mirror_url "$url")"
  if have curl; then curl -fsSL --connect-timeout 10 --max-time 300 "$url" | bash -s -- "$@"; else wget -qO- --timeout=300 "$url" | bash -s -- "$@"; fi
}

# --- Node.js 获取 ---------------------------------------------------------
# 优先用系统已有的 node / Homebrew / nodesource；都拿不到时用官方 tarball
# 装一份“免 root、免 Homebrew”的私有运行时（macOS 没装 brew 时唯一可行路径）。
# 目录沿用 pi 官方 installer 的布局（<data>/pi-node/current），两者可共用。
node_standalone_base_dir() {
  if [ -n "${XDG_DATA_HOME:-}" ]; then printf '%s/pi-node' "$XDG_DATA_HOME"
  else printf '%s/.local/share/pi-node' "$HOME"; fi
}
node_standalone_bin_dir() { printf '%s/current/bin' "$(node_standalone_base_dir)"; }

load_node_standalone() {
  local bindir; bindir="$(node_standalone_bin_dir)"
  [ -x "$bindir/node" ] || return 1
  PATH="$bindir:$PATH"; export PATH
  hash -r 2>/dev/null || true
  return 0
}

# install_node_standalone：下载 + sha256 校验 + 解包到 node_standalone_base_dir。
install_node_standalone() {
  local platform arch base tmp file verifier
  case "$OS" in
    macos) platform=darwin ;;
    linux) platform=linux ;;
    *) return 1 ;;
  esac
  case "$ARCH" in
    x86_64) arch=x64 ;;
    arm64) arch=arm64 ;;
    *) return 1 ;;
  esac
  have curl || { err "$(lc 'standalone Node.js install needs curl' '独立安装 Node.js 需要 curl')"; return 1; }
  if have sha256sum; then verifier=sha256sum
  elif have shasum; then verifier=shasum
  else err "$(lc 'need sha256sum or shasum to verify the Node.js download' '需要 sha256sum 或 shasum 校验 Node.js 下载')"; return 1; fi

  base="$(node_standalone_base_dir)"
  tmp="$(mktemp -d "${TMPDIR:-/tmp}/aicli-node.XXXXXX")" || return 1
  info "$(lc "installing standalone Node.js (no root, no Homebrew) into $base" "正在安装独立 Node.js（免 root / Homebrew）到 $base")"
  curl -fsSL --connect-timeout 10 --max-time 300 -o "$tmp/SHASUMS256.txt" \
    "${NODE_DIST:-$NODE_DIST_OFFICIAL}/latest-v22.x/SHASUMS256.txt" || { rm -rf "$tmp"; return 1; }
  # 只挑本平台的 .tar.gz：.tar.xz 在精简系统上可能缺 xz
  file="$(awk -v suffix="-$platform-$arch.tar.gz" \
    'index($2, "node-v") == 1 && substr($2, length($2) - length(suffix) + 1) == suffix { print $2; exit }' \
    "$tmp/SHASUMS256.txt")"
  if [ -z "$file" ]; then
    rm -rf "$tmp"
    err "$(lc "no Node.js build published for ${platform}-${arch}" "官方没有 ${platform}-${arch} 的 Node.js 构建")"
    return 1
  fi
  curl -fsSL --connect-timeout 10 --max-time 600 -o "$tmp/$file" \
    "${NODE_DIST:-$NODE_DIST_OFFICIAL}/latest-v22.x/$file" || { rm -rf "$tmp"; return 1; }
  if [ "$verifier" = "sha256sum" ]; then
    (cd "$tmp" && awk -v f="$file" '$2 == f' SHASUMS256.txt | sha256sum -c -) >&2 || { rm -rf "$tmp"; err "$(lc 'Node.js checksum mismatch' 'Node.js 校验和不匹配')"; return 1; }
  else
    (cd "$tmp" && awk -v f="$file" '$2 == f' SHASUMS256.txt | shasum -a 256 -c -) >&2 || { rm -rf "$tmp"; err "$(lc 'Node.js checksum mismatch' 'Node.js 校验和不匹配')"; return 1; }
  fi
  mkdir -p "$base" || { rm -rf "$tmp"; return 1; }
  tar -xzf "$tmp/$file" -C "$base" || { rm -rf "$tmp"; return 1; }
  rm -f "$base/current"
  ln -s "$base/${file%.tar.gz}" "$base/current" || { rm -rf "$tmp"; return 1; }
  rm -rf "$tmp"
  ok "$(lc "Node.js -> $base/current/bin/node" "Node.js -> $base/current/bin/node")"
  return 0
}

ensure_node() {
  have node && return 0
  # 上次已经装过独立 Node（但当前 shell 没 source rc）→ 直接复用，别再下 50MB
  if load_node_standalone && have node; then
    info "$(lc "reusing standalone Node.js at $(node_standalone_bin_dir)" "复用已装的独立 Node.js：$(node_standalone_bin_dir)")"
    return 0
  fi
  # OpenWrt/musl：没有 apt，glibc 的 Node 也跑不起来，明确报可理解的错
  if is_musl_system; then
    err "$(lc 'this musl system (OpenWrt etc.) cannot run Node.js here; install node inside a Debian/Alpine docker container or skip agents that need it (pi/omo/omp/codex)' '此 musl 系统（OpenWrt 等）无法直接运行 Node.js；请在 Debian/Alpine Docker 容器里装 node，或跳过需要它的 agent（pi/omo/omp/codex）')"
    return 1
  fi
  warn "$(lc 'node not found; installing Node.js (Homebrew/nodesource, else a no-root standalone build)' '未找到 node；开始安装 Node.js（Homebrew/nodesource，失败则改用免 root 的独立包）')"
  if [ "$OS" = "macos" ]; then
    have brew && { brew install node || true; }
  else
    # 非 root 时优先 sudo（没装 sudo 就直连 apt-get，失败也只是报错）
    local sudo_cmd=""
    if ! is_root; then have sudo && sudo_cmd="sudo"; fi
    curl -fsSL https://deb.nodesource.com/setup_22.x | $sudo_cmd bash - >/dev/null 2>&1 || true
    $sudo_cmd apt-get install -y nodejs >/dev/null 2>&1 || true
  fi
  have node && return 0
  # 兜底：官方 tarball 独立安装。macOS 上没装 Homebrew 时这是唯一可行路径。
  if install_node_standalone && load_node_standalone; then
    persist_path "$(node_standalone_bin_dir)"
    return 0
  fi
  err "$(lc 'node install failed' 'node 安装失败')"
  return 1
}

ensure_npm() {
  ensure_node || return 1
  have npm && return 0
  # 独立安装的 Node 自带 npm；PATH 未生效时直接从 node 同级目录取。
  local bindir; bindir="$(node_standalone_bin_dir)"
  if [ -x "$bindir/npm" ]; then
    PATH="$bindir:$PATH"; export PATH
    hash -r 2>/dev/null || true
    have npm && return 0
  fi
  err "$(lc 'npm not found' '未找到 npm')"
  return 1
}

# npm 安装包装：国内网络走镜像 registry；失败再做一次官方源重试（镜像缺包时兜底）。
npm_g() {
  local pkg="$*"
  if [ -n "${NPM_CONFIG_REGISTRY:-}" ]; then
    npm install -g --ignore-scripts $pkg --registry="$NPM_CONFIG_REGISTRY" && return 0
    warn "$(lc "mirror install of $pkg failed; retrying official registry" "镜像安装 $pkg 失败，改用官方源重试")"
    npm install -g --ignore-scripts $pkg --registry=https://registry.npmjs.org/ && return 0
    return 1
  fi
  npm install -g --ignore-scripts $pkg
}

install_pi() {
  if have pi; then info "$(lc 'pi already installed, updating' 'pi 已安装，检查更新')"; pi update >/dev/null 2>&1 || true; return 0; fi
  # npm 优先：完全非交互，且不会接管终端。
  # 官方 install.sh 在 stdout 是 tty 时会 `exec pi`（"Start pi now? [Y/n]" 默认 Y），
  # 把本脚本的终端吞掉——用户看到的就是那个 pi TUI 界面卡住。所以只有在 npm
  # 不可用时才走官方 installer，并且用 subshell + 重定向彻底隔断它的交互。
  if ensure_npm; then
    if npm install -g --ignore-scripts @earendil-works/pi-coding-agent; then return 0; fi
    warn "$(lc 'npm install failed; falling back to the official installer' 'npm 安装失败；改用官方 installer')"
  fi
  run_official_isolated https://pi.dev/install.sh
}

# 官方 installer 的危险行为：pi 的 install.sh 在 stdout 是 tty 时会 `exec pi`，
# 直接把本脚本的终端交给 pi 的 TUI（用户看到的就是“装完卡在 pi 界面”）；
# 而它的确认提示读的是 /dev/tty，脚本无法喂输入 → 挂死。
# 注意：只重定向 stdout 不够 —— 只要进程还有控制终端，`( : <>/dev/tty )` 就成立。
# 必须用 setsid 让子进程脱离控制终端，它才会走非交互分支。
detach_mechanism() {
  if have setsid; then printf 'setsid'
  elif have perl; then printf 'perl'
  elif have python3; then printf 'python3'
  fi
}

# detach_run <mechanism> <cmd> [args...]：在无控制终端的新会话里执行 cmd。
detach_run() {
  local m="$1"; shift
  case "$m" in
    setsid)  setsid "$@" ;;
    perl)    perl -e 'use POSIX (); POSIX::setsid() or exit 1; exec @ARGV or exit 1' "$@" ;;
    python3) python3 -c 'import os,sys; os.setsid(); os.execvp(sys.argv[1],sys.argv[1:])' "$@" ;;
    *) return 1 ;;
  esac
}

# run_official_isolated <url>：跑官方安装脚本，但剥夺它的控制终端。
run_official_isolated() {
  local url="$1" m
  need_dl || return 1
  m="$(detach_mechanism)"
  if [ -z "$m" ]; then
    err "$(lc 'cannot run the official installer without hijacking the terminal (needs setsid, perl, or python3); install Node.js + npm first' '无法在不劫持终端的前提下运行官方 installer（需要 setsid、perl 或 python3）；请先装好 Node.js + npm')"
    return 1
  fi
  if have curl; then curl -fsSL --connect-timeout 10 --max-time 300 "$(gh_mirror_url "$url")" | detach_run "$m" bash
  else wget -qO- --timeout=300 "$(gh_mirror_url "$url")" | detach_run "$m" bash
  fi
}
install_omo() {
  export OMO_INSTALL_ALLOW_SUDO=1   # 服务器常以 root 运行
  if have omo; then info "$(lc 'omo already installed, updating' 'omo 已安装，检查更新')"; omo update >/dev/null 2>&1 || true; return 0; fi
  if have curl; then curl -fsSL --connect-timeout 10 --max-time 300 "$(gh_mirror_url https://get.omo.dev/install.sh)" | bash
  elif have wget; then wget -qO- --timeout=300 "$(gh_mirror_url https://get.omo.dev/install.sh)" | bash
  else ensure_npm && npm_g omo-ai; fi
}
install_claude() {
  if have claude; then info "$(lc 'claude already installed' 'claude 已安装')"; return 0; fi
  if have curl; then curl -fsSL --connect-timeout 10 --max-time 300 "$(gh_mirror_url https://claude.ai/install.sh)" | bash
  elif have wget; then wget -qO- --timeout=300 "$(gh_mirror_url https://claude.ai/install.sh)" | bash
  else ensure_npm && npm_g @anthropic-ai/claude-code; fi
}
install_codex() {
  if have codex; then info "$(lc 'codex already installed' 'codex 已安装')"; return 0; fi
  ensure_npm && npm_g @openai/codex
}
install_grok() {
  export PATH="$HOME/.grok/bin:$PATH"
  if have grok; then info "$(lc 'grok already installed' 'grok 已安装')"; return 0; fi
  run_official https://x.ai/cli/install.sh || return 1
  export PATH="$HOME/.grok/bin:$PATH"
  have grok || { err "$(lc 'grok install failed' 'grok 安装失败')"; return 1; }
}
# omp（@oh-my-pi/pi-coding-agent）：官方 installer 优先（自带 sha256 校验与可运行性
# 自检），失败再退 npm/bun 全局安装。二进制落在 ~/.local/bin，bun 安装落在 ~/.bun/bin。
install_omp() {
  export PATH="$HOME/.local/bin:$HOME/.bun/bin:$PATH"
  if have omp; then info "$(lc 'omp already installed, updating' 'omp 已安装，检查更新')"; omp update >/dev/null 2>&1 || true; return 0; fi
  if have curl; then
    curl -fsSL --connect-timeout 10 --max-time 300 https://omp.sh/install | sh && { export PATH="$HOME/.local/bin:$PATH"; have omp && return 0; }
  fi
  if have bun; then
    bun install -g @oh-my-pi/pi-coding-agent && return 0
  fi
  if ensure_npm; then
    npm_g @oh-my-pi/pi-coding-agent && return 0
  fi
  err "$(lc 'omp install failed (need curl+sh, bun, or npm)' 'omp 安装失败（需要 curl+sh、bun 或 npm）')"
  return 1
}
# musl 系统（OpenWrt/iStoreOS/Alpine 等）检测。
# 官方安装器靠 "ldd --version | grep musl" 判 musl，但 OpenWrt 的 busybox
# ldd 不输出 musl 字样 -> 误装 glibc 版 -> musl 无 glibc 加载器，exec 失败，
# shell 报 "not found"。此处用更可靠的探测。
is_musl_system() {
  [ -f /lib/ld-musl-x86_64.so.1 ] || [ -f /lib/ld-musl-aarch64.so.1 ] && return 0
  [ -f /etc/alpine-release ] && return 0
  [ -f /etc/openwrt_release ] && return 0
  ldd --version 2>&1 | grep -qi musl && return 0
  grep -qi musl /etc/os-release 2>/dev/null && return 0
  return 1
}

# 直接安装官方 musl 变体到 ~/.opencode/bin
install_opencode_musl() {
  local arch="x64"
  case "$(uname -m)" in
    aarch64|arm64) arch="arm64" ;;
  esac
  local url; url="$(gh_mirror_url "https://github.com/anomalyco/opencode/releases/latest/download/opencode-linux-${arch}-musl.tar.gz")"
  local bindir="$HOME/.opencode/bin" tmpd
  mkdir -p "$bindir"
  tmpd="$(mktemp -d "${TMPDIR:-/tmp}/aicli-oc.XXXXXX")" || return 1
  info "$(lc "downloading opencode musl build (${arch})" "下载 opencode musl 构建（${arch}）")"
  if have curl; then
    curl -fsSL --connect-timeout 10 --max-time 300 -o "$tmpd/oc.tar.gz" "$url" || { rm -rf "$tmpd"; return 1; }
  else
    wget -q --timeout=300 -O "$tmpd/oc.tar.gz" "$url" || { rm -rf "$tmpd"; return 1; }
  fi
  tar -xzf "$tmpd/oc.tar.gz" -C "$bindir" || { rm -rf "$tmpd"; return 1; }
  rm -rf "$tmpd"
  chmod +x "$bindir/opencode" 2>/dev/null || true
  # 必须真实可执行才算成功
  "$bindir/opencode" --version >/dev/null 2>&1 || {
    err "$(lc 'musl build still fails to run on this system' 'musl 构建在本系统仍无法运行')"
    return 1
  }
  ok "opencode (musl) -> $bindir/opencode"
  return 0
}

install_opencode() {
  # 已装且能真正执行才算已安装（musl 系统上装坏的 glibc 二进制 command -v 命中但无法 exec）
  if command -v opencode >/dev/null 2>&1 && opencode --version >/dev/null 2>&1; then
    info "$(lc 'opencode already installed' 'opencode 已安装')"; return 0
  fi
  # musl 系统：绕过官方安装器的误检测，直接装 musl 变体
  if [ "$OS" = "linux" ] && is_musl_system; then
    install_opencode_musl && return 0
    warn "$(lc 'musl install failed; trying the official installer' 'musl 安装失败；尝试官方安装器')"
  fi
  if run_official https://opencode.ai/install; then
    hash -r 2>/dev/null || true
    have opencode && return 0
    # 官方装器把二进制放进本次新增目录（如 ~/.opencode/bin），当前 PATH 还没有
    if [ -x "$HOME/.opencode/bin/opencode" ]; then
      ok "opencode -> $HOME/.opencode/bin/opencode"
      return 0
    fi
    return 0   # 安装器已报成功，PATH 交给 post_install_check 提示
  fi
  # 官方安装器失败（国内常见：卡在 GitHub 下载）→ 直接抓 release（套反代）
  if install_opencode_release; then return 0; fi
  ensure_npm && npm_g opencode-ai
}

# install_opencode_release：绕过 opencode.ai/install，直连 GitHub release 下载二进制。
# 国内走 gh_proxy_prefix 反代；先试反代，失败再试原始 URL。
install_opencode_release() {
  local arch="x64" url out tmpd bindir ext
  case "$(uname -m)" in aarch64|arm64) arch="arm64" ;; esac
  bindir="$HOME/.opencode/bin"; mkdir -p "$bindir"
  tmpd="$(mktemp -d "${TMPDIR:-/tmp}/aicli-ocr.XXXXXX")" || return 1
  case "$OS" in
    macos) [ "$ARCH" = "arm64" ] && out="opencode-darwin-arm64" || out="opencode-darwin-x64"; ext="zip" ;;
    *) out="opencode-linux-${arch}"; ext="tar.gz" ;;
  esac
  url="$(gh_mirror_url "https://github.com/anomalyco/opencode/releases/latest/download/${out}.${ext}")"
  info "$(lc "downloading opencode release ($OS/$arch)" "直接下载 opencode release：$OS/$arch")"
  if have curl; then
    curl -fsSL --connect-timeout 10 --max-time 300 -o "$tmpd/pkg" "$url" || { rm -rf "$tmpd"; return 1; }
  else
    wget -q --timeout=300 -O "$tmpd/pkg" "$url" || { rm -rf "$tmpd"; return 1; }
  fi
  if [ "$ext" = "zip" ]; then
    ( cd "$tmpd" && unzip -oq pkg -d unpacked ) || { rm -rf "$tmpd"; return 1; }
    # zip 内可能带子目录，找可执行文件
    local f; f="$(find "$tmpd/unpacked" -type f -name 'opencode*' 2>/dev/null | head -1)"
    [ -n "$f" ] || { rm -rf "$tmpd"; return 1; }
    cp "$f" "$bindir/opencode"
  else
    tar -xzf "$tmpd/pkg" -C "$bindir" || { rm -rf "$tmpd"; return 1; }
  fi
  rm -rf "$tmpd"
  chmod +x "$bindir/opencode" 2>/dev/null || true
  "$bindir/opencode" --version >/dev/null 2>&1 || { err "$(lc 'opencode release binary does not run on this system' 'opencode release 二进制在本系统无法运行')"; return 1; }
  ok "opencode -> $bindir/opencode"
  return 0
}

# persist_path <dir>：让“以后新开的 shell”都能找到 dir 里的命令。
# OpenWrt/ash 不读 .bashrc，所以优先写 /etc/profile.d/；否则写用户 shell rc。
persist_path() {
  local bindir="$1" sub line
  [ -n "$bindir" ] || return 0
  case "$bindir" in
    "$HOME"/*) sub="${bindir#"$HOME"/}" ;;
    *) sub="" ;;
  esac
  if [ -z "$sub" ]; then
    line="export PATH=\"$bindir:\$PATH\""
  else
    line="export PATH=\"\$HOME/$sub:\$PATH\""
  fi
  local marker="${sub:-$bindir}"
  if [ -d /etc/profile.d ] && [ -w /etc/profile.d ]; then
    local prof="/etc/profile.d/ai-cli-setup.sh"
    if ! grep -q "$marker" "$prof" 2>/dev/null; then
      printf '%s\n' "$line" >> "$prof"
      info "$(lc "added PATH to $prof" "已把 PATH 写入 $prof")"
    fi
    return 0
  fi
  local rcfile; rcfile="$(detect_shellrc)"
  if [ -n "$rcfile" ] && ! grep -q "$marker" "$rcfile" 2>/dev/null; then
    printf '\n# added by ai-cli-setup\n%s\n' "$line" >> "$rcfile"
    info "$(lc "added PATH to $rcfile" "已把 PATH 写入 $rcfile")"
  fi
  return 0
}

# 安装后清 bash 命令路径缓存并确认二进制真实可用：
# npm 重装会把 bin 换位置，bash 缓存的旧路径（如 /usr/local/bin/codex）导致
# "No such file or directory"，hash -r 后用真实路径再探测。
# 返回 0 仅当二进制真实可执行；否则返回 1，让安装阶段如实报 FAIL。
post_install_check() {
  local a="$1" bin path bindir
  bin="$(agent_bin "$a")"
  hash -r 2>/dev/null || true
  if path="$(command -v "$bin" 2>/dev/null)" && [ -x "$path" ]; then
    ok "$(agent_title "$a") -> $path"
    return 0
  fi
  # 二进制可能在本次安装新增的 PATH 目录里，当前 shell 尚未包含
  for bindir in "$HOME/.local/bin" "$(node_standalone_bin_dir)" "$HOME/.grok/bin" "$HOME/.bun/bin" "$HOME/.opencode/bin"; do
    if [ -x "$bindir/$bin" ]; then
      ok "$(agent_title "$a") -> $bindir/$bin"
      # 1) 本脚本本次运行用得到：立即把该目录塞进当前 PATH
      case ":$PATH:" in *":$bindir:"*) ;; *) PATH="$bindir:$PATH" ;; esac
      export PATH
      # 2) 让以后每个 shell 都找得到（写 profile.d / shell rc）
      persist_path "$bindir"
      # 3) 关键：写 profile.d 只对“之后新开的登录 shell”生效，当前正在跑的这个 shell
      #    永远不会重读 profile。BusyBox/OpenWrt 上软链进总是存在于 PATH 的目录
      #    （/usr/local/bin 或 /usr/bin），让用户当前终端与新终端都能直接敲命令。
      if link_into_path "$bindir/$bin" "$bin"; then
        info "$(lc "linked $bin -> $LINKED_INTO (already on PATH; works in the current shell)" "已软链 $bin -> ${LINKED_INTO}（该目录已在 PATH；当前终端即可直接使用）")"
        return 0
      fi
      info "$(lc "current shell: run this first" "当前终端先执行")  export PATH=\"$bindir:\$PATH\""
      return 0
    fi
  done
  err "$(lc "$bin not installed (install step did not produce a runnable binary)" "$bin 未安装成功（安装步骤没有产出可执行文件）")"
  return 1
}

# link_into_path <src> <name>：把 src 软链到一个“本来就存在于 PATH、且大多数 shell
# 无需重读 profile 即可解析”的目录，返回 0 表示成功（LINKED_INTO 记录目标目录）。
# 找不到可写目录时返回 1，由调用方退回“export PATH”提示。
LINKED_INTO=""
link_into_path() {
  local src="$1" name="$2" d
  [ -x "$src" ] || return 1
  LINKED_INTO=""
  for d in /usr/local/bin /usr/bin /bin; do
    [ -d "$d" ] && [ -w "$d" ] || continue
    # 只覆盖指向同一二进制的链接或已失效链接；不碰用户自己的真实文件
    if [ -e "$d/$name" ] && [ ! -L "$d/$name" ]; then continue; fi
    if ln -sf "$src" "$d/$name" 2>/dev/null; then
      LINKED_INTO="$d"
      return 0
    fi
  done
  return 1
}

install_agent() {
  local a="$1"
  step "$(lc "install $(agent_title "$a")" "安装 $(agent_title "$a")")"
  if [ "$SKIP_INSTALL" -eq 1 ]; then info "$(lc 'skip-install: not touching the binary' '--skip-install：跳过安装')"; return 0; fi
  if [ "$DRY_RUN" -eq 1 ]; then info "$(lc 'dry-run: would install' 'dry-run：将安装') $(agent_title "$a")"; return 0; fi
  local rc=0
  case "$a" in
    pi) install_pi || rc=$? ;;
    omo) install_omo || rc=$? ;;
    omp) install_omp || rc=$? ;;
    claude) install_claude || rc=$? ;;
    codex) install_codex || rc=$? ;;
    grok) install_grok || rc=$? ;;
    opencode) install_opencode || rc=$? ;;
  esac
  # 安装命令自身失败就不再探测二进制（避免把“装失败”报成 OK）
  [ "$rc" -eq 0 ] || return "$rc"
  post_install_check "$a"
}

# ============================================================
# 8. 模型列表拉取
# ============================================================
# 纯 bash 把多行合并为逗号分隔（OpenWrt/BusyBox 没有 paste）
join_lines() {
  local out="" l
  while IFS= read -r l; do
    [ -n "$l" ] || continue
    out="${out:+$out,}$l"
  done
  printf '%s' "$out"
}
fetch_models() {
  local base="$1" key="${2:-}" url
  [ -n "$base" ] || return 1
  base="${base%/}"
  case "$base" in */v1) url="$base/models" ;; *) url="$base/v1/models" ;; esac
  local tmp; tmp="$(mktemp "${TMPDIR:-/tmp}/aicli-models.XXXXXX")" || return 1
  if have curl; then
    # shellcheck disable=SC2086
    curl -fsS --connect-timeout 10 --max-time 30 ${key:+-H "Authorization: Bearer $key"} -o "$tmp" "$url" 2>/dev/null || { rm -f "$tmp"; return 1; }
  else
    # shellcheck disable=SC2086
    wget -q --timeout=30 ${key:+--header="Authorization: Bearer $key"} -O "$tmp" "$url" 2>/dev/null || { rm -f "$tmp"; return 1; }
  fi
  local ids=""
  if have jq; then ids="$(jq -r '((.data // .models // [])[] | (.id // .name // .slug // empty))' < "$tmp" 2>/dev/null | head -200 | join_lines)"
  elif have node; then ids="$(node -e 'let s="";process.stdin.on("data",d=>s+=d).on("end",()=>{try{const d=JSON.parse(s);let a=d.data||d.models||[];if(!Array.isArray(a))a=Object.values(a);for(const x of a){const v=typeof x==="string"?x:(x&&(x.id||x.name||x.slug));if(v)console.log(v)}}catch(e){}}' < "$tmp" | head -200 | join_lines)"
  elif have python3; then ids="$(python3 -c 'import json,sys
try: d=json.load(sys.stdin)
except Exception: sys.exit(0)
a=d.get("data") or d.get("models") or []
if isinstance(a,dict): a=list(a.values())
for x in a:
    v = x if isinstance(x,str) else (x.get("id") or x.get("name") or x.get("slug") if isinstance(x,dict) else None)
    if v: print(v)' < "$tmp" | head -200 | join_lines)"
  fi
  rm -f "$tmp"
  [ -n "$ids" ] || return 1
  printf '%s' "$ids"
}

# ============================================================
# 9. JSON 工具（无 jq 依赖）
# ============================================================
json_read_str() {  # json_read_str <file> <pyexpr> — 用 node 或 python3 读 JSON 字符串
  local f="$1" expr="$2"
  if have node; then node -e 'const c=require(process.argv[1]); console.log(eval(process.argv[2]))' "$f" "$expr" 2>/dev/null
  elif have python3; then python3 -c "import json,sys; d=json.load(open(sys.argv[1])); print(eval(sys.argv[2]))" "$f" "$expr" 2>/dev/null
  fi
}

# ============================================================
# 10. 配置写入（每个 agent 一个函数；原子写 + 备份 + 600）
# ============================================================
backup_file() {
  local f="$1" bak
  [ -f "$f" ] || return 0
  bak="${f}.bak.$(date +%Y%m%d%H%M%S)"
  if cp -p "$f" "$bak"; then
    chmod 600 "$bak" 2>/dev/null || true
    info "$(lc "backed up: $f -> $bak" "已备份：$f -> $bak")"
  fi
}
write_600() {  # write_600 <target> <tmpfile>
  chmod 600 "$2" 2>/dev/null || true
  mv -f "$2" "$1"
  chmod 600 "$1" 2>/dev/null || true
}

toml_escape() {
  local s="${1:-}"
  s="${s//\\/\\\\}"; s="${s//\"/\\\"}"
  s="${s//$'\n'/\\n}"; s="${s//$'\r'/\\r}"; s="${s//$'\t'/\\t}"
  printf '%s' "$s"
}

json_escape() {
  local s="${1:-}" out=""
  # 注意：node/python3 “存在但执行失败”时也会返回空——所以先取输出、校验非空，
  # 失败再落到纯 bash 转义，避免把空串写进配置（软路由上曾出现 key 变空）。
  if have node; then out="$(node -e 'console.log(JSON.stringify(process.argv[1]))' "$s" 2>/dev/null || true)"
  elif have python3; then out="$(python3 -c 'import json,sys; print(json.dumps(sys.argv[1]))' "$s" 2>/dev/null || true)"
  fi
  if [ -n "$out" ]; then printf '%s' "$out"; return 0; fi
  s="${s//\\/\\\\}"; s="${s//\"/\\\"}"
  s="${s//$'\n'/\\n}"; s="${s//$'\r'/\\r}"; s="${s//$'\t'/\\t}"
  printf '"%s"' "$s"
}

# --- pi / omo：结构相同（models.json + settings.json） ---
# agent_dir: ~/.pi/agent 或 ~/.omo/agent
write_pi_like() {
  local agent_dir="$2" provider="$3"
  local mfile="$agent_dir/models.json" sfile="$agent_dir/settings.json"
  if [ "$DRY_RUN" -eq 0 ]; then
    mkdir -p "$agent_dir"
    backup_file "$mfile"; backup_file "$sfile"
  fi

  local mjson sjson tmpm
  mjson="$(build_pi_models_json "$provider")"
  [ -n "$mjson" ] || { err "$(lc 'failed to build models.json (need node/python3)' '生成 models.json 失败（需要 node/python3）')"; return 1; }
  sjson="$(build_pi_settings_json "$provider" || true)"

  tmpm="$(mktemp "${TMPDIR:-/tmp}/aicli-m.XXXXXX")"; printf '%s\n' "$mjson" > "$tmpm"
  if [ "$DRY_RUN" -eq 1 ]; then
    info "dry-run: $mfile / $sfile"; rm -f "$tmpm"; return 0
  fi
  write_600 "$mfile" "$tmpm"
  ok "$(lc "wrote $mfile" "已写入 $mfile")"
  if [ -n "$sjson" ]; then
    local tmps; tmps="$(mktemp "${TMPDIR:-/tmp}/aicli-s.XXXXXX")"
    printf '%s\n' "$sjson" > "$tmps"
    write_600 "$sfile" "$tmps"
    ok "$(lc "wrote $sfile" "已写入 $sfile")"
  else
    warn "$(lc 'no default model chosen; settings.json untouched' '未指定默认模型；settings.json 未改动')"
  fi
}

build_pi_models_json() {
  local provider="$1" out=""
  if have node; then
    out="$(PI_PROVIDER="$provider" PI_BASE_URL="$BASE_URL" PI_API_KEY="$API_KEY" PI_MODELS="$MODELS" \
      node -e '
        const env = process.env;
        const models = (env.PI_MODELS||"").split(",").map(s=>s.trim()).filter(Boolean);
        const out = {providers:{}};
        out.providers[env.PI_PROVIDER] = {
          baseUrl: env.PI_BASE_URL, api: "openai-completions",
          apiKey: env.PI_API_KEY,
          models: models.map(m=>({id:m, name:m}))
        };
        process.stdout.write(JSON.stringify(out,null,2)+"\n");
      ' 2>/dev/null || true)"
  elif have python3; then
    out="$(PI_PROVIDER="$provider" PI_BASE_URL="$BASE_URL" PI_API_KEY="$API_KEY" PI_MODELS="$MODELS" \
      python3 -c '
import json,os
env=os.environ
models=[m.strip() for m in env.get("PI_MODELS","").split(",") if m.strip()]
out={"providers":{env["PI_PROVIDER"]:{"baseUrl":env["PI_BASE_URL"],"api":"openai-completions","apiKey":env["PI_API_KEY"],"models":[{"id":m,"name":m} for m in models]}}}
print(json.dumps(out,indent=2))
' 2>/dev/null || true)"
  fi
  if [ -n "$out" ] && [ "${out#\{}" != "$out" ]; then printf '%s' "$out"; return 0; fi
  # 纯 bash 兜底（OpenWrt/BusyBox 等无 node/python3）：手工拼 JSON 并转义
  local m first=1
  printf '{\n  "providers": {\n    "%s": {\n' "$(printf '%s' "$provider" | sed 's/"/\\"/g')"
  printf '      "baseUrl": %s,\n' "$(json_escape "$BASE_URL")"
  printf '      "api": "openai-completions",\n'
  printf '      "apiKey": %s,\n' "$(json_escape "$API_KEY")"
  printf '      "models": [\n'
  for m in $(printf '%s' "$MODELS" | tr ',' ' '); do
    [ -n "$m" ] || continue
    [ "$first" = "1" ] || printf ',\n'
    printf '        { "id": %s, "name": %s }' "$(json_escape "$m")" "$(json_escape "$m")"
    first=0
  done
  printf '\n      ]\n    }\n  }\n}\n'
}

# defaultModel 为纯模型 id（不带 provider 前缀）
build_pi_settings_json() {
  local provider="${1:-}" first=""
  # BusyBox 的 tr 不认 [:space:]（会当字面字符集删字母），用显式空白字符
  [ -n "$MODELS" ] && first="$(printf '%s' "$MODELS" | cut -d, -f1 | tr -d ' \t\r\n')"
  [ -z "$first" ] && first="$MODEL"
  [ -z "$first" ] && return 1
  [ -n "$provider" ] || provider="$(provider_from_host)"
  printf '{\n  "defaultProvider": "%s",\n  "defaultModel": "%s"\n}\n' \
    "$(printf '%s' "$provider" | sed 's/"/\\"/g')" "$(printf '%s' "$first" | sed 's/"/\\"/g')"
}

provider_from_host() {
  printf '%s' "${BASE_URL:-}" | sed -E 's#^https?://##; s#/.*$##; s#[^A-Za-z0-9]+#-#g' | sed 's/^-//; s/-$//'
}

# --- claude：写 ~/.claude/settings.json（env 块） ---
write_claude() {
  local dir f model tmp
  dir="${CLAUDE_CONFIG_DIR:-$HOME/.claude}"; f="$dir/settings.json"
  model="${MODEL:-}"
  [ -z "$model" ] && [ -n "$MODELS" ] && model="$(printf '%s' "$MODELS" | cut -d, -f1)"
  # Claude Code 自己在 base 后拼 /v1/messages，必须写不带 /v1 的根地址
  local base_clean="${BASE_URL%/}"
  base_clean="${base_clean%/v1}"
  if [ "$DRY_RUN" -eq 0 ]; then
    mkdir -p "$dir"
    backup_file "$f"
  fi
  tmp="$(mktemp "${TMPDIR:-/tmp}/aicli-c.XXXXXX")"
  if have node; then
    CLAUDE_FILE="$f" CLAUDE_OUT="$tmp" CLAUDE_BASE="$base_clean" CLAUDE_KEY="$API_KEY" CLAUDE_MODEL="$model" \
    node -e '
      const fs=require("fs"),env=process.env;
      let cfg={};
      if(fs.existsSync(env.CLAUDE_FILE)){try{cfg=JSON.parse(fs.readFileSync(env.CLAUDE_FILE,"utf8"))}catch(e){}}
      if(!cfg||typeof cfg!=="object"||Array.isArray(cfg)) cfg={};
      cfg.env=Object.assign({},cfg.env,{
        ANTHROPIC_BASE_URL:env.CLAUDE_BASE,
        ANTHROPIC_AUTH_TOKEN:env.CLAUDE_KEY,
        ...(env.CLAUDE_MODEL?{ANTHROPIC_MODEL:env.CLAUDE_MODEL}:{})
      });
      fs.writeFileSync(env.CLAUDE_OUT, JSON.stringify(cfg,null,2)+"\n");
    ' 2>/dev/null || true
  fi
  if [ ! -s "$tmp" ]; then
    # 纯 bash 兜底（无 node，如 OpenWrt）：保留已有键用 sed 合并 env 三个变量；
    # 复杂度可控——只在已有文件是合法 JSON 对象时做键级替换，否则全新生成
    if [ -f "$f" ] && grep -q '"env"' "$f" 2>/dev/null; then
      sed \
        -e 's#"ANTHROPIC_BASE_URL"[^,}]*#"ANTHROPIC_BASE_URL": "'"$(printf '%s' "$base_clean" | sed 's/[&/]/\\&/g')"'"#' \
        -e 's#"ANTHROPIC_AUTH_TOKEN"[^,}]*#"ANTHROPIC_AUTH_TOKEN": "'"$(printf '%s' "$API_KEY" | sed 's/[&/]/\\&/g')"'"#' \
        "$f" > "$tmp"
      if [ -n "$model" ]; then
        if grep -q '"ANTHROPIC_MODEL"' "$tmp" 2>/dev/null; then
          sed 's#"ANTHROPIC_MODEL"[^,}]*#"ANTHROPIC_MODEL": "'"$(printf '%s' "$model" | sed 's/[&/]/\\&/g')"'"#' "$tmp" > "${tmp}.m" 2>/dev/null && mv -f "${tmp}.m" "$tmp" || true
        else
          # 键不存在：AUTH_TOKEN 值后插入（BSD/GNU sed 通用：无 \n，用逗号前置换行需求为零的行内追加）
          # 若替换后 JSON 仍不合法，最终 write 前有 node 侧校验兜底；musl 无 node 时
          # 该分支仅影响已有配置缺 MODEL 键的罕见场景，退化为不写 MODEL（claude 会用默认）。
          local msafe; msafe="$(printf '%s' "$model" | sed 's/[&/]/\\&/g')"
          sed -e 's#"ANTHROPIC_AUTH_TOKEN"\([^,}]*\)#"ANTHROPIC_AUTH_TOKEN"\1, "ANTHROPIC_MODEL": "'"$msafe"'"#' "$tmp" > "${tmp}.m" 2>/dev/null && mv -f "${tmp}.m" "$tmp" || true
        fi
      fi
      warn "$(lc 'no node; merged env keys into existing settings.json (backed up)' '无 node；已合并 env 键到现有 settings.json（已备份）')"
    else
      {
        printf '{\n'
        printf '  "env": {\n'
        printf '    "ANTHROPIC_BASE_URL": "%s",\n' "$(printf '%s' "$base_clean" | sed 's/"/\\"/g')"
        printf '    "ANTHROPIC_AUTH_TOKEN": "%s"' "$(printf '%s' "$API_KEY" | sed 's/"/\\"/g')"
        [ -n "$model" ] && printf ',\n    "ANTHROPIC_MODEL": "%s"' "$(printf '%s' "$model" | sed 's/"/\\"/g')"
        printf '\n  }\n}\n'
      } > "$tmp"
      warn "$(lc 'no node; wrote a fresh settings.json (previous file backed up)' '无 node；已生成全新 settings.json（旧文件已备份）')"
    fi
  fi
  [ -s "$tmp" ] || { err "$(lc 'failed to build claude settings.json' '生成 claude settings.json 失败')"; rm -f "$tmp"; return 1; }
  if [ "$DRY_RUN" -eq 1 ]; then info "dry-run: $f"; rm -f "$tmp"; return 0; fi
  write_600 "$f" "$tmp"
  ok "$(lc "wrote $f" "已写入 $f")"
  info "$(lc "run: source or restart shell, then claude" "新开终端或 source 后运行 claude")"
}

# --- codex：写 ~/.codex/config.toml + auth.json ---
write_codex() {
  local dir="$HOME/.codex" cf="$HOME/.codex/config.toml" af="$HOME/.codex/auth.json"
  local model="${MODEL:-}"
  [ -z "$model" ] && [ -n "$MODELS" ] && model="$(printf '%s' "$MODELS" | cut -d, -f1)"
  [ -n "$model" ] || model="gpt-5.5"
  # wire_api：默认 responses（OpenAI 官方），部分网关只支持 chat
  local wire="${CODEX_WIRE_API:-responses}"
  if [ "$DRY_RUN" -eq 0 ]; then
    mkdir -p "$dir"
    backup_file "$cf"; backup_file "$af"
  fi
  local base_nov1="${BASE_URL%/}"
  base_nov1="${base_nov1%/v1}"
  local tmp; tmp="$(mktemp "${TMPDIR:-/tmp}/aicli-x.XXXXXX")"
  {
    printf 'model_provider = "OpenAI"\n'
    printf 'model = "%s"\n' "$(toml_escape "$model")"
    printf 'review_model = "%s"\n\n' "$(toml_escape "$model")"
    printf '[model_providers.OpenAI]\n'
    printf 'name = "OpenAI"\n'
    printf 'base_url = "%s"\n' "$(toml_escape "$base_nov1")"
    printf 'wire_api = "%s"\n' "$wire"
    printf 'requires_openai_auth = true\n'
  } > "$tmp"
  if [ "$DRY_RUN" -eq 1 ]; then info "dry-run: $cf / $af"; rm -f "$tmp"; return 0; fi
  write_600 "$cf" "$tmp"
  local tmpa; tmpa="$(mktemp "${TMPDIR:-/tmp}/aicli-a.XXXXXX")"
  printf '{"OPENAI_API_KEY": %s}\n' "$(json_escape "$API_KEY")" > "$tmpa"
  write_600 "$af" "$tmpa"
  ok "$(lc "wrote $cf + $af" "已写入 $cf + $af")"
}

# --- grok：写 ~/.grok/config.toml ---
write_grok() {
  local f="$HOME/.grok/config.toml"
  local model="${MODEL:-}"
  [ -z "$model" ] && [ -n "$MODELS" ] && model="$(printf '%s' "$MODELS" | cut -d, -f1)"
  [ -n "$model" ] || model="grok-4.7"
  local alias="${GROK_ALIAS:-main}"
  if [ "$DRY_RUN" -eq 0 ]; then
    mkdir -p "$HOME/.grok"
    backup_file "$f"
  fi
  local tmp; tmp="$(mktemp "${TMPDIR:-/tmp}/aicli-g.XXXXXX")"
  {
    printf '[cli]\ninstaller = "internal"\n\n'
    printf '[models]\ndefault = "%s"\n\n' "$(toml_escape "$alias")"
    printf '[model.%s]\n' "$(toml_escape "$alias")"
    printf 'model = "%s"\n' "$(toml_escape "$model")"
    printf 'base_url = "%s"\n' "$(toml_escape "$BASE_URL")"
    printf 'api_key = "%s"\n' "$(toml_escape "$API_KEY")"
    printf 'context_window = %s\n' "${GROK_CONTEXT_WINDOW:-500000}"
    printf 'supports_reasoning_effort = true\n'
    printf 'reasoning_efforts = ["low", "medium", "high"]\n\n'
    printf '[features]\ntelemetry = false\nfeedback = false\n\n'
    printf '[telemetry]\ntrace_upload = false\nmixpanel_enabled = false\n'
  } > "$tmp"
  if [ "$DRY_RUN" -eq 1 ]; then info "dry-run: $f"; rm -f "$tmp"; return 0; fi
  write_600 "$f" "$tmp"
  ok "$(lc "wrote $f" "已写入 $f")"
}

# --- opencode：合并写入 opencode.json ---
write_opencode() {
  local f="${XDG_CONFIG_HOME:-$HOME/.config}/opencode/opencode.json"
  local model="${MODEL:-}"
  [ -z "$model" ] && [ -n "$MODELS" ] && model="$(printf '%s' "$MODELS" | cut -d, -f1)"
  [ "$DRY_RUN" -eq 1 ] || mkdir -p "$(dirname "$f")"
  [ "$DRY_RUN" -eq 1 ] || backup_file "$f"
  local provider provider_name npm_pkg
  case "$(printf '%s' "$BASE_URL" | tr 'A-Z' 'a-z')" in
    *openrouter.ai*) provider="openrouter"; provider_name="OpenRouter"; npm_pkg="" ;;
    *api.deepseek.com*) provider="deepseek"; provider_name="DeepSeek"; npm_pkg="@ai-sdk/openai-compatible" ;;
    *api.openai.com*) provider="openai"; provider_name="OpenAI"; npm_pkg="" ;;
    *generativelanguage.googleapis.com*) provider="google"; provider_name="Google"; npm_pkg="" ;;
    *open.bigmodel.cn*) provider="zhipuglm"; provider_name="智谱 GLM"; npm_pkg="@ai-sdk/openai-compatible" ;;
    *)
      provider="$(provider_from_host)"
      provider_name="$(printf '%s' "$BASE_URL" | sed -E 's#^https?://##; s#/.*$##')"
      npm_pkg="@ai-sdk/openai-compatible" ;;
  esac
  # V2 检测：用户显式 AICLI_OPENCODE_V2，或已装二进制 major >= 2，或配置里已有 providers 键。
  # 注意 `opencode --version` 输出形如 "opencode v2.0.26"（带前缀），不能锚定 ^2。
  # dry-run 下不执行二进制（它会自建 cache/state/log 目录），只按配置判断。
  local ocv=1
  local prov_upper; prov_upper="$(printf '%s' "$provider" | tr 'a-z-' 'A-Z_')"
  if [ -n "${AICLI_OPENCODE_V2:-}" ]; then
    case "$AICLI_OPENCODE_V2" in 1|true|yes) ocv=2 ;; *) ocv=1 ;; esac
  elif [ "$DRY_RUN" -eq 0 ] && have opencode; then
    local ocout
    ocout="$(opencode --version 2>/dev/null || true)"
    case "$(printf '%s' "$ocout" | sed -nE 's/.*[^0-9]([0-9]+)\.[0-9]+.*/\1/p' | head -1)" in
      ''|1) ocv=1 ;;
      *) ocv=2 ;;
    esac
    if [ "$ocv" = "1" ] && grep -q '"providers"' "$f" 2>/dev/null; then ocv=2; fi
  elif grep -q '"providers"' "$f" 2>/dev/null; then
    ocv=2
  fi

  local env_var="AICLI_${prov_upper}_API_KEY"
  local tmp; tmp="$(mktemp "${TMPDIR:-/tmp}/aicli-o.XXXXXX")"
  if [ "$ocv" = "2" ]; then
    # ---- OpenCode V2：providers/settings/package + {env:} 凭据引用 ----
    # key 不落盘：写入 {env:VAR} 引用，真实 key 在写盘后导出到 shell 配置
    # （导出与是否有 node 无关，见函数末尾）。
    if have node; then
    OC_FILE="$f" OC_OUT="$tmp" OC_PROVIDER="$provider" OC_NAME="$provider_name" \
    OC_PACKAGE="aisdk:${npm_pkg:-@ai-sdk/openai-compatible}" \
    OC_BASE="$BASE_URL" OC_KEYREF="{env:$env_var}" OC_MODELS="$MODELS" OC_DEFAULT="$model" \
    node -e '
      const fs=require("fs"),env=process.env;
      let cfg={};
      if(fs.existsSync(env.OC_FILE)){try{cfg=JSON.parse(fs.readFileSync(env.OC_FILE,"utf8"))}catch(e){}}
      if(!cfg||typeof cfg!=="object"||Array.isArray(cfg)) cfg={};
      cfg.$schema=cfg.$schema||"https://opencode.ai/config.json";
      cfg.providers=cfg.providers||{};
      const p=cfg.providers[env.OC_PROVIDER]=cfg.providers[env.OC_PROVIDER]||{};
      if(env.OC_NAME)p.name=env.OC_NAME;
      p.package=env.OC_PACKAGE;
      p.settings=Object.assign({},p.settings,{baseURL:env.OC_BASE,apiKey:env.OC_KEYREF});
      const models=(env.OC_MODELS||"").split(",").map(s=>s.trim()).filter(Boolean);
      p.models=p.models||{};
      for(const m of models){if(!p.models[m])p.models[m]={name:m.split("/").pop()}}
      if(env.OC_DEFAULT)cfg.model=env.OC_PROVIDER+"/"+env.OC_DEFAULT;
      fs.writeFileSync(env.OC_OUT,JSON.stringify(cfg,null,2)+"\n");
    '
    fi   # have node (V2)
  else
    # ---- OpenCode V1：provider/options/npm，key 直写 ----
    if have node; then
    OC_FILE="$f" OC_OUT="$tmp" OC_PROVIDER="$provider" OC_NAME="$provider_name" OC_NPM="$npm_pkg" \
    OC_BASE="$BASE_URL" OC_KEY="$API_KEY" OC_MODELS="$MODELS" OC_DEFAULT="$model" \
    node -e '
      const fs=require("fs"),env=process.env;
      let cfg={};
      if(fs.existsSync(env.OC_FILE)){try{cfg=JSON.parse(fs.readFileSync(env.OC_FILE,"utf8"))}catch(e){}}
      if(!cfg||typeof cfg!=="object"||Array.isArray(cfg)) cfg={};
      cfg.$schema=cfg.$schema||"https://opencode.ai/config.json";
      cfg.provider=cfg.provider||{};
      const p=cfg.provider[env.OC_PROVIDER]=cfg.provider[env.OC_PROVIDER]||{};
      if(env.OC_NAME)p.name=env.OC_NAME;
      if(env.OC_NPM)p.npm=env.OC_NPM;
      p.options=Object.assign({},p.options,{baseURL:env.OC_BASE,apiKey:env.OC_KEY});
      const models=(env.OC_MODELS||"").split(",").map(s=>s.trim()).filter(Boolean);
      p.models=p.models||{};
      for(const m of models){if(!p.models[m])p.models[m]={name:m.split("/").pop()}}
      if(env.OC_DEFAULT)cfg.model=env.OC_PROVIDER+"/"+env.OC_DEFAULT;
      fs.writeFileSync(env.OC_OUT,JSON.stringify(cfg,null,2)+"\n");
    '
    fi   # have node (V1)
  fi
  if [ ! -s "$tmp" ] && ! have node; then
    # 纯 bash 兜底（OpenWrt 等无 node 环境）：生成全新配置；旧文件已备份
    local m first=""
    {
      printf '{\n'
      printf '  "$schema": "https://opencode.ai/config.json",\n'
      if [ "$ocv" = "2" ]; then
        printf '  "model": "%s/%s",\n' "$provider" "${model:-$(printf '%s' "$MODELS" | cut -d, -f1)}"
        printf '  "providers": {\n'
        printf '    "%s": {\n' "$provider"
        printf '      "name": "%s",\n' "$provider_name"
        printf '      "package": "aisdk:@ai-sdk/openai-compatible",\n'
        printf '      "settings": { "baseURL": "%s", "apiKey": "{env:AICLI_%s_API_KEY}" },\n' \
          "$(printf '%s' "$BASE_URL" | sed 's/"/\\"/g')" "$(printf '%s' "$provider" | tr 'a-z-' 'A-Z_')"
        printf '      "models": {\n'
        first=1
        for m in $(printf '%s' "$MODELS" | tr ',' ' '); do
          [ -n "$m" ] || continue
          [ "$first" = "1" ] || printf ',\n'
          printf '        "%s": { "name": "%s" }' "$(printf '%s' "$m" | sed 's/"/\\"/g')" "$(printf '%s' "$m" | sed 's/"/\\"/g; s/.*\///')"
          first=0
        done
        printf '\n      }\n'
        printf '    }\n  }\n}\n'
      else
        printf '  "model": "%s/%s",\n' "$provider" "${model:-$(printf '%s' "$MODELS" | cut -d, -f1)}"
        printf '  "provider": {\n'
        printf '    "%s": {\n' "$provider"
        printf '      "name": "%s",\n' "$provider_name"
        printf '      "npm": "@ai-sdk/openai-compatible",\n'
        printf '      "options": { "baseURL": "%s", "apiKey": "%s" },\n' \
          "$(printf '%s' "$BASE_URL" | sed 's/"/\\"/g')" "$(printf '%s' "$API_KEY" | sed 's/"/\\"/g')"
        printf '      "models": {\n'
        first=1
        for m in $(printf '%s' "$MODELS" | tr ',' ' '); do
          [ -n "$m" ] || continue
          [ "$first" = "1" ] || printf ',\n'
          printf '        "%s": { "name": "%s" }' "$(printf '%s' "$m" | sed 's/"/\\"/g')" "$(printf '%s' "$m" | sed 's/"/\\"/g; s/.*\///')"
          first=0
        done
        printf '\n      }\n'
        printf '    }\n  }\n}\n'
      fi
    } > "$tmp"
    warn "$(lc 'no node; wrote a fresh opencode.json (previous file backed up)' '无 node；已生成全新 opencode.json（旧文件已备份）')"
  fi
  [ -s "$tmp" ] || { err "$(lc 'failed to build opencode.json' '生成 opencode.json 失败')"; rm -f "$tmp"; return 1; }
  if [ "$DRY_RUN" -eq 1 ]; then info "dry-run: $f"; rm -f "$tmp"; return 0; fi
  write_600 "$f" "$tmp"
  if [ "$ocv" = "2" ]; then
    # 配置里只有 {env:VAR} 引用，真实 key 必须落到 shell 配置，否则 opencode 拿不到凭据。
    export_oc_key "$env_var" "$provider"
  fi
  ok "$(lc "wrote $f" "已写入 $f") [v$ocv]"
  info "$(lc 'provider' 'provider')  $provider  $(lc 'default model' '默认模型')  ${model:-(none)}"
}

# 把 OpenCode V2 的网关密钥写进 shell 配置（配置文件只留 {env:} 引用）。
# 有 node 时用 node 做精确改写，否则纯 bash/python3 兜底；都没有则追加一行。
export_oc_key() {
  local env_var="$1" provider="$2" shellrc
  shellrc="$(detect_shellrc)"
  [ -n "$shellrc" ] || return 0
  if [ ! -f "$shellrc" ]; then
    mkdir -p "$(dirname "$shellrc")" 2>/dev/null || true
    : > "$shellrc" 2>/dev/null || return 0
  fi
  if grep -q "^export ${env_var}=" "$shellrc" 2>/dev/null; then
    if have node; then
      SHELLRC="$shellrc" ENVVAR="$env_var" KEYVAL="$API_KEY" node -e '
        const fs=require("fs"),e=process.env;
        const re=new RegExp("^export "+e.ENVVAR+"=.*$","m");
        const v="export "+e.ENVVAR+"="+JSON.stringify(e.KEYVAL).replace(/^"|"$/g,"\x27").replace(/\x27/g,"\x27\\\x27\x27");
        fs.writeFileSync(e.SHELLRC, fs.readFileSync(e.SHELLRC,"utf8").replace(re, v));
      ' 2>/dev/null || true
    elif have python3; then
      python3 - "$shellrc" "$env_var" "$API_KEY" <<'PYK' 2>/dev/null || true
import sys, re
path, var, val = sys.argv[1], sys.argv[2], sys.argv[3]
s = open(path).read()
s = re.sub(r"^export %s=.*$" % var, "export %s='%s'" % (var, val.replace("'", "'\\''")), s, flags=re.M)
open(path, "w").write(s)
PYK
    else
      # 无 node/python3：先删旧行再追加，避免留下两条互相覆盖的 export
      local rest; rest="$(grep -v "^export ${env_var}=" "$shellrc" 2>/dev/null || true)"
      { printf '%s\n' "$rest"; printf 'export %s=%s\n' "$env_var" "'$API_KEY'"; } > "${shellrc}.aicli.tmp" \
        && mv -f "${shellrc}.aicli.tmp" "$shellrc" || rm -f "${shellrc}.aicli.tmp"
    fi
    info "$(lc "updated $env_var in $shellrc" "已更新 $shellrc 中的 $env_var")"
  else
    printf '\n# %s gateway key (added by ai-cli-setup)\nexport %s=%s\n' "$provider" "$env_var" "'$API_KEY'" >> "$shellrc"
    info "$(lc "exported $env_var in $shellrc (key not stored in opencode.json)" "已在 $shellrc 导出 ${env_var}（key 不写入 opencode.json）")"
  fi
  # 写进 shell 配置只对新开的 shell 生效；当前终端里的 opencode 会拿不到凭据。
  # 提示里不回显明文密钥——终端可能被录屏/滚屏留存，照抄 shell 配置里那一行即可。
  info "$(lc "current shell: run this first" "当前终端先执行")  source ${shellrc}   $(lc "(or open a new terminal)" "（或新开一个终端）")"
}

# --- omp：写 ~/.omp/agent/models.yml（providers）+ config.yml（modelRoles.default） ---
# omp 不支持环境变量插值（apiKey: ${VAR} 不会被展开），key 只能明文写入，故强制 600。
write_omp() {
  local dir="$HOME/.omp/agent"
  local mfile="$dir/models.yml" cfile="$dir/config.yml"
  local model="${MODEL:-}"
  [ -z "$model" ] && [ -n "$MODELS" ] && model="$(printf '%s' "$MODELS" | cut -d, -f1 | tr -d ' \t\r\n')"
  local provider; provider="$(provider_from_host)"
  if [ "$DRY_RUN" -eq 0 ]; then
    mkdir -p "$dir"
    backup_file "$mfile"; backup_file "$cfile"
  fi
  local tmpm; tmpm="$(mktemp "${TMPDIR:-/tmp}/aicli-omp-m.XXXXXX")"
  local tmpc; tmpc="$(mktemp "${TMPDIR:-/tmp}/aicli-omp-c.XXXXXX")"

  yaml_omp_provider_block "$provider" > "$tmpm.blk"
  yaml_upsert_block "$mfile" "$provider" "$tmpm.blk" > "$tmpm"
  rm -f "$tmpm.blk"
  omp_set_default_role "$cfile" "$provider" "$model" > "$tmpc"

  if [ "$DRY_RUN" -eq 1 ]; then
    info "dry-run: $mfile / $cfile"
    rm -f "$tmpm" "$tmpc"; return 0
  fi
  [ -s "$tmpm" ] || { err "$(lc 'failed to build models.yml' '生成 models.yml 失败')"; rm -f "$tmpm" "$tmpc"; return 1; }
  write_600 "$mfile" "$tmpm"
  ok "$(lc "wrote $mfile" "已写入 $mfile")"
  if [ -s "$tmpc" ]; then
    write_600 "$cfile" "$tmpc"
    ok "$(lc "wrote $cfile" "已写入 $cfile")"
  else
    warn "$(lc 'no default model chosen; config.yml untouched' '未指定默认模型；config.yml 未改动')"
    rm -f "$tmpc"
  fi
  info "$(lc 'provider' 'provider')  $provider  $(lc 'default model' '默认模型')  ${model:-(none)}"
}

# YAML 双引号标量转义（够用于 baseUrl / apiKey / 模型 id）
yaml_quote() {
  local s="${1:-}"
  s="${s//\\/\\\\}"; s="${s//\"/\\\"}"
  printf '"%s"' "$s"
}

# YAML 映射键 / 纯标量：安全字符（字母数字 . _ - /）直接裸写，否则加双引号。
# 裸写更贴近 omp 自己 `omp config set` 的产物（如 `default: gw/model`），
# 也便于文本级合并时匹配。
yaml_key() {
  case "${1:-}" in
    ''|*[!A-Za-z0-9._/-]*) yaml_quote "$1" ;;
    *) printf '%s' "$1" ;;
  esac
}

# 生成 <provider> 的 models.yml 片段（缩进 2 空格，属于 providers: 之下）
yaml_omp_provider_block() {
  local provider="$1" m
  printf '  %s:\n' "$(yaml_key "$provider")"
  printf '    baseUrl: %s\n' "$(yaml_quote "$BASE_URL")"
  printf '    api: openai-completions\n'
  printf '    apiKey: %s\n' "$(yaml_quote "$API_KEY")"
  printf '    models:\n'
  for m in $(printf '%s' "$MODELS" | tr ',' ' '); do
    [ -n "$m" ] || continue
    printf '      - id: %s\n' "$(yaml_quote "$m")"
    printf '        name: %s\n' "$(yaml_quote "$m")"
  done
}

# yaml_upsert_block <file> <key> <blockfile>：把 blockfile 内容作为 file 里顶层
# `providers:` 映射中 key 的子块写入（已存在则整块替换），其余内容原样保留。
# 纯 awk 实现（OpenWrt/BusyBox 无 yq）；文件不存在/为空时新建 providers 段。
yaml_upsert_block() {
  local file="$1" key="$2" block="$3"
  if [ ! -s "$file" ]; then
    printf 'providers:\n'
    cat "$block"
    return 0
  fi
  awk -v key="$(yaml_key "$key")" -v keyq="$(yaml_quote "$key")" -v blockfile="$block" '
    BEGIN {
      while ((getline l < blockfile) > 0) blk[++nb] = l
      inprov = 0; skipping = 0; inserted = 0
    }
    {
      line = $0
      if (line ~ /^providers:[[:space:]]*$/) { inprov = 1; print; next }
      if (inprov && line ~ /^[^[:space:]#]/) {
        if (!inserted) { for (i = 1; i <= nb; i++) print blk[i]; inserted = 1 }
        inprov = 0
      }
      if (inprov) {
        if (line == "  " key ":" || line == "  " keyq ":") { skipping = 1; next }
        if (skipping) {
          if (line ~ /^  [^[:space:]]/) { skipping = 0 }
          else { next }
        }
      }
      print
    }
    END {
      if (inprov && !inserted) { for (i = 1; i <= nb; i++) print blk[i]; inserted = 1 }
      if (!inserted) { print "providers:"; for (i = 1; i <= nb; i++) print blk[i] }
    }
  ' "$file"
}

# omp_set_default_role <config.yml> <provider> <model>：保留 config.yml 的其它设置，
# 只把 modelRoles.default 指向 provider/model。优先用 `omp config set`（保留 smol/slow
# 等其它角色并经 schema 校验），omp 不可用时退回文本级块替换。
omp_set_default_role() {
  local cfile="$1" provider="$2" model="$3"
  [ -n "$model" ] || return 0
  local selector="$provider/$model"
  # `omp config set modelRoles` 会整体替换该记录，所以必须先成功读出已有角色
  # 再合并；读不到就退回文本级替换（那个分支只改 default 一行，绝不丢角色）。
  if [ "$DRY_RUN" -eq 0 ] && have omp && have python3; then
    local roles_raw roles merged
    if roles_raw="$(omp config get modelRoles --json 2>/dev/null)"; then
      roles="$(printf '%s' "$roles_raw" | python3 -c '
import json,sys
try:
    d = json.load(sys.stdin)
    v = d.get("value") or {}
    print(json.dumps(v) if isinstance(v, dict) else "{}")
except Exception:
    print("{}")
' 2>/dev/null || true)"
      [ -n "$roles" ] || roles="{}"
      merged="$(ROLES="$roles" SEL="$selector" python3 -c '
import json,os
r = json.loads(os.environ["ROLES"] or "{}")
r["default"] = os.environ["SEL"]
print(json.dumps(r))
' 2>/dev/null || true)"
      if [ -n "$merged" ] && omp config set modelRoles "$merged" >/dev/null 2>&1; then
        # omp 写它自己的 config.yml；只有确实读到非空内容才算成功，
        # 否则（例如 omp 指向了别的 profile）退回下面的文本级替换。
        if [ -s "$cfile" ]; then
          cat "$cfile"
          return 0
        fi
      fi
    fi
  fi
  # 文本级兜底：只改 modelRoles 下的 default 行，smol/slow 等其它角色原样保留。
  local sel_v; sel_v="$(yaml_key "$selector")"
  if [ -s "$cfile" ]; then
    awk -v sel="$sel_v" '
      BEGIN { inroles = 0; seen = 0; hadroles = 0 }
      /^modelRoles:[[:space:]]*$/ {
        inroles = 1; hadroles = 1; print; next
      }
      inroles && /^[^[:space:]#]/ { inroles = 0 }
      inroles && /^[[:space:]]+default:[[:space:]]/ { print "  default: " sel; seen = 1; next }
      { print }
      END {
        if (hadroles && !seen) print "  default: " sel
        if (!hadroles) { print "modelRoles:"; print "  default: " sel }
      }
    ' "$cfile"
  else
    printf 'modelRoles:\n  default: %s\n' "$sel_v"
  fi
}

configure_agent() {
  local a="$1"
  step "$(lc "configure $(agent_title "$a")" "配置 $(agent_title "$a")")"
  if [ -z "$BASE_URL" ] || [ -z "$API_KEY" ]; then
    info "$(lc 'no credentials; skipping config' '未提供凭据；跳过配置')"; return 0
  fi
  case "$a" in
    pi)     write_pi_like pi "$HOME/.pi/agent" "$(provider_from_host)" ;;
    omo)    write_pi_like omo "$HOME/.omo/agent" "$(provider_from_host)" ;;
    omp)    write_omp ;;
    claude) write_claude ;;
    codex)  write_codex ;;
    grok)   write_grok ;;
    opencode) write_opencode ;;
  esac
}

# ============================================================
# 11. 交互：语言 → agent
# ============================================================
agent_at_index() {
  local want="$1" i=1 a
  for a in $ALL_AGENTS; do [ "$i" -eq "$want" ] && { printf '%s' "$a"; return 0; }; i=$((i+1)); done
  return 1
}
agent_count() { local a n=0; for a in $ALL_AGENTS; do n=$((n+1)); done; printf '%s' "$n"; }

parse_selection() {
  local spec="$1" tok lo hi i out="" a max
  spec="$(printf '%s' "$spec" | tr ',' ' ')"
  max="$(agent_count)"
  # 空输入或回车默认全选
  if [ -z "$(printf '%s' "$spec" | tr -d ' \t\r\n')" ]; then
    printf '%s' "$ALL_AGENTS" | tr ' ' ','
    return 0
  fi
  for tok in $spec; do
    tok="$(printf '%s' "$tok" | tr '[:upper:]' '[:lower:]')"
    case "$tok" in a|all|'*') printf '%s' "$ALL_AGENTS" | tr ' ' ','; return 0 ;; esac
    [ "$tok" = "0" ] || [ "$tok" = "$((max + 1))" ] && { printf '%s' "$ALL_AGENTS" | tr ' ' ','; return 0; }
    case "$tok" in *-*) lo="${tok%%-*}"; hi="${tok##*-}" ;; *) lo="$tok"; hi="$tok" ;; esac
    case "$lo" in ''|*[!0-9]*) return 1 ;; esac
    case "$hi" in ''|*[!0-9]*) return 1 ;; esac
    [ "$lo" -ge 1 ] && [ "$hi" -le "$max" ] && [ "$lo" -le "$hi" ] || return 1
    for i in $(seq "$lo" "$hi"); do
      a="$(agent_at_index "$i")" || return 1
      case ",$out," in *",$a,"*) continue ;; esac
      out="${out:+$out,}$a"
    done
  done
  [ -n "$out" ] || return 1
  printf '%s' "$out"
}

prompt_language() {
  [ "$LANG_EXPLICIT" -eq 1 ] && return 0
  local ans="" def_num="2"
  [ "$LANG_CODE" = "en" ] && def_num="1"
  printf '\n%s\n\n' "${BOLD}Select language  /  选择语言${RESET}" >&2
  printf '  1) English\n  2) 中文 (Chinese)\n\n' >&2
  read_line ans "choose / 请选择 [1/2, default: $def_num] "
  [ -z "$ans" ] && ans="$def_num"
  case "$(printf '%s' "$ans" | tr '[:upper:]' '[:lower:]')" in
    2|zh|cn|chinese|中文) LANG_CODE="zh" ;;
    1|en|english) LANG_CODE="en" ;;
  esac
}

prompt_agents() {
  local a i=1 all_key ans picked label n
  all_key=$(( $(agent_count) + 1 ))
  printf '\n%s\n\n' "${BOLD}$(lc 'Which AI agents do you want to install?' '要安装哪些 AI agent？')${RESET}" >&2
  for a in $ALL_AGENTS; do
    local bin status
    bin="$(agent_bin "$a")"
    if have "$bin"; then
      status="${GREEN}$(lc 'installed' '已安装')${RESET}"
    else
      status="${DIM}$(lc 'not installed' '未安装')${RESET}"
    fi
    printf '  %s) %-12s %-32s [%s]\n' "$i" "$(agent_title "$a")" "${DIM}$(agent_homepage "$a")${RESET}" "$status" >&2
    i=$((i+1))
  done
  printf '  %s) %-12s %s\n\n' "$all_key" "$(lc 'All above' '以上全部')" "${CYAN}[$(lc 'default: Enter' '默认: 直接回车')]${RESET}" >&2
  printf '%s\n\n' "${DIM}$(lc "  one number = single   |   1,3 or 1-3 = several   |   Enter or a = all" "  单个数字 = 单选   |   1,3 或 1-3 = 多选   |   回车 或 a = 全部")${RESET}" >&2
  for _ in 1 2 3; do
    read_line ans "$(lc 'select' '请选择') [1-$all_key, $(lc 'default' '默认'): $all_key] "
    [ -z "$ans" ] && ans="$all_key"
    if picked="$(parse_selection "$ans")"; then
      SELECTED="$picked"; label=""; n=0
      for a in $(printf '%s' "$picked" | tr ',' ' '); do label="${label:+$label, }$(agent_title "$a")"; n=$((n+1)); done
      info "$(lc "selected: $label" "已选择：$label")"
      [ "$n" -eq "$(agent_count)" ] && info "$(lc 'all agents will be set up' '将安装全部 agent')"
      return 0
    fi
    warn "$(lc "invalid choice: ${ans:-<empty>}" "无效选择：${ans:-<空>}")"
  done
  die "$(lc 'nothing selected' '未选择任何工具')"
}

# 探测本地各 agent 已有的 Base URL 与 Key（用于交互时贴心回车复用）
EXISTING_BASE_URL=""
EXISTING_API_KEY=""
detect_existing_credentials() {
  EXISTING_BASE_URL=""
  EXISTING_API_KEY=""
  local cf="${CLAUDE_CONFIG_DIR:-$HOME/.claude}/settings.json"
  local pf="$HOME/.pi/agent/models.json"
  local gf="$HOME/.grok/config.toml"
  local xf="$HOME/.codex/auth.json"

  if [ -f "$cf" ]; then
    [ -z "$EXISTING_BASE_URL" ] && EXISTING_BASE_URL="$(grep -m1 '"ANTHROPIC_BASE_URL"' "$cf" 2>/dev/null | sed -E 's/.*"ANTHROPIC_BASE_URL"[[:space:]]*:[[:space:]]*"([^"]+)".*/\1/' || true)"
    [ -z "$EXISTING_API_KEY" ] && EXISTING_API_KEY="$(grep -m1 '"ANTHROPIC_AUTH_TOKEN"' "$cf" 2>/dev/null | sed -E 's/.*"ANTHROPIC_AUTH_TOKEN"[[:space:]]*:[[:space:]]*"([^"]+)".*/\1/' || true)"
  fi
  if [ -f "$pf" ]; then
    [ -z "$EXISTING_BASE_URL" ] && EXISTING_BASE_URL="$(grep -m1 '"baseUrl"' "$pf" 2>/dev/null | sed -E 's/.*"baseUrl"[[:space:]]*:[[:space:]]*"([^"]+)".*/\1/' || true)"
    [ -z "$EXISTING_API_KEY" ] && EXISTING_API_KEY="$(grep -m1 '"apiKey"' "$pf" 2>/dev/null | sed -E 's/.*"apiKey"[[:space:]]*:[[:space:]]*"([^"]+)".*/\1/' || true)"
  fi
  if [ -f "$gf" ]; then
    [ -z "$EXISTING_BASE_URL" ] && EXISTING_BASE_URL="$(grep -m1 'base_url' "$gf" 2>/dev/null | sed -E 's/.*base_url[[:space:]]*=[[:space:]]*"([^"]+)".*/\1/' || true)"
    [ -z "$EXISTING_API_KEY" ] && EXISTING_API_KEY="$(grep -m1 'api_key' "$gf" 2>/dev/null | sed -E 's/.*api_key[[:space:]]*=[[:space:]]*"([^"]+)".*/\1/' || true)"
  fi
  if [ -f "$xf" ] && [ -z "$EXISTING_API_KEY" ]; then
    EXISTING_API_KEY="$(grep -m1 '"OPENAI_API_KEY"' "$xf" 2>/dev/null | sed -E 's/.*"OPENAI_API_KEY"[[:space:]]*:[[:space:]]*"([^"]+)".*/\1/' || true)"
  fi
}

# ============================================================
# 12. 凭据收集（安装完成后、配置前）
# ============================================================
collect_credentials() {
  local need_models=0 need_model=0 a
  for a in $(printf '%s' "$SELECTED" | tr ',' ' '); do
    agent_needs_models "$a" && need_models=1
    agent_needs_model "$a" && need_model=1
  done

  detect_existing_credentials

  if [ -z "$BASE_URL" ]; then
    [ "$NON_INTERACTIVE" -eq 1 ] && die "$(lc 'missing --base-url' '缺少 --base-url')"
    local prompt_base
    if [ -n "$EXISTING_BASE_URL" ]; then
      prompt_base="$(lc "API endpoint base URL [default: $EXISTING_BASE_URL]" "接口 base URL [默认: $EXISTING_BASE_URL]") "
    else
      prompt_base="$(lc 'API endpoint base URL (e.g. https://api.example.com/v1)' '接口 base URL（例：https://api.example.com/v1）') "
    fi
    read_line BASE_URL "$prompt_base"
    [ -z "$BASE_URL" ] && BASE_URL="$EXISTING_BASE_URL"
    [ -n "$BASE_URL" ] || die "$(lc 'base URL is required' 'base URL 必填')"
  fi
  if [ -z "$API_KEY" ]; then
    [ "$NON_INTERACTIVE" -eq 1 ] && die "$(lc 'missing --api-key' '缺少 --api-key')"
    local prompt_key
    if [ -n "$EXISTING_API_KEY" ]; then
      prompt_key="$(lc "API key [Enter to keep: $(secret_mask "$EXISTING_API_KEY")]" "API key [回车保留已有密钥: $(secret_mask "$EXISTING_API_KEY")]") "
    else
      prompt_key="$(lc 'API key' 'API key') "
    fi
    read_line API_KEY "$prompt_key" 1
    [ -z "$API_KEY" ] && API_KEY="$EXISTING_API_KEY"
    [ -n "$API_KEY" ] || die "$(lc 'API key is required' 'API key 必填')"
  fi
  if [ "$need_models" -eq 1 ] && [ -z "$MODELS" ]; then
    info "$(lc 'fetching model list from the endpoint...' '正在从端点获取模型列表...')"
    local fetched=""
    fetched="$(fetch_models "$BASE_URL" "$API_KEY" || true)"
    if [ -n "$fetched" ]; then
      local mcount
      mcount="$(printf '%s' "$fetched" | tr ',' '\n' | grep -c . || true)"
      if [ "${mcount:-0}" -gt 20 ]; then
        printf '%s\n' "$(lc "found $mcount models:" "发现 $mcount 个模型：")" >&2
        printf '%s' "$fetched" | tr ',' '\n' | head -20 | sed 's/^/  /' >&2
        printf '  %s\n' "$(lc "… (+$((mcount - 20)) more; blank = all $mcount)" "…（还有 $((mcount - 20)) 个；留空 = 全部 $mcount 个）")" >&2
      else
        info "$(lc "found models: $fetched" "发现模型：$fetched")"
      fi
      if [ "$NON_INTERACTIVE" -eq 1 ]; then MODELS="$fetched"
      else
        local ans=""
        read_line ans "$(lc 'model ids to register (comma separated, blank = all)' '要写入的模型 id（逗号分隔，留空 = 全部）') "
        [ -n "$ans" ] && MODELS="$ans" || MODELS="$fetched"
      fi
    elif [ "$NON_INTERACTIVE" -eq 1 ]; then
      warn "$(lc 'could not fetch models; pass --models a,b' '无法获取模型列表；请用 --models a,b 指定')"
    else
      local need_any=0 a2
      for a2 in $(printf '%s' "$SELECTED" | tr ',' ' '); do agent_needs_models "$a2" && need_any=1; done
      if [ "$need_any" -eq 1 ]; then
        local _eg=0
        while [ -z "$MODELS" ]; do
          read_line MODELS "$(lc 'model ids (comma separated, required)' '模型 id（逗号分隔，必填）') "
          [ "$READ_EOF" = "1" ] && _eg=$((_eg + 1)) || _eg=0
          [ "$_eg" -ge 2 ] && die "$(lc 'stdin exhausted; rerun with --models a,b' '输入已耗尽；请加 --models a,b 重跑')"
          [ -z "$MODELS" ] && warn "$(lc 'at least one model is required' '至少需要一个模型')"
        done
      fi
    fi
  fi
  # 单默认模型（claude/codex/grok/opencode）：必填。
  # 留空会让 claude 用官方默认模型名（如 claude-opus-5-5），网关不认识就报错。
  if [ "$need_model" -eq 1 ] && [ -z "$MODEL" ]; then
    if [ -n "$MODELS" ]; then
      MODEL="$(printf '%s' "$MODELS" | cut -d, -f1 | tr -d ' \t\r\n')"
      info "$(lc "default model: $MODEL (first of the list; rerun with --model to change)" "默认模型：${MODEL}（列表第一个；要换请用 --model 重跑）")"
    elif [ "$NON_INTERACTIVE" -eq 0 ]; then
      local _eofguard=0
      while [ -z "$MODEL" ]; do
        read_line MODEL "$(lc 'default model id (REQUIRED, must exist on the gateway, e.g. group/auto-claude-sonnet-5-5)' '默认模型 id（必填，须为网关上真实存在的，如 group/auto-claude-sonnet-5-5）') "
        [ "$READ_EOF" = "1" ] && _eofguard=$((_eofguard + 1)) || _eofguard=0
        [ "$_eofguard" -ge 2 ] && die "$(lc 'stdin exhausted before a default model was given; rerun with --model <id>' '输入已耗尽仍未提供默认模型；请加 --model <id> 重跑')"
        [ -z "$MODEL" ] && warn "$(lc 'a default model is required; leaving it empty breaks claude/codex on custom gateways' '默认模型必填；留空会让 claude 用官方模型名，自定义网关会报错')"
      done
    fi
  fi
  return 0   # 防 set -e：上方条件表达式为假时函数会以返回码 1 结束，被 set -e 杀掉
}

# ============================================================
# 13. 命令
# ============================================================
cmd_list() {
  printf '\n%s\n\n' "${BOLD}$(lc 'supported agents' '支持的 agent')"
  local a bin
  for a in $ALL_AGENTS; do
    bin="$(agent_bin "$a")"
    if have "$bin"; then
      printf '  %s  %-10s %s\n' "${GREEN}✓${RESET}" "$(agent_title "$a")" "$(command -v "$bin")"
    else
      printf '  %s  %-10s %s\n' "${YELLOW}·${RESET}" "$(agent_title "$a")" "${DIM}$(lc 'not installed' '未安装')${RESET}"
    fi
  done
  printf '\n'
}

cmd_doctor() {
  printf '\n%s\n\n' "${BOLD}$(lc 'environment check' '环境检查')"
  printf '  %-14s %s\n' "$(lc 'platform' '平台')" "$OS / $ARCH"
  printf '  %-14s %s\n' "$(lc 'user' '用户')" "$(id -un) (uid=$(id -u))"
  printf '  %-14s %s\n' "$(lc 'home' '家目录')" "$HOME"
  printf '  %-14s %s\n' "$(lc 'language' '语言')" "$LANG_CODE"
  printf '\n%s\n' "${BOLD}$(lc 'commands' '命令')${RESET}"
  local c
  for c in curl wget node npm python3 jq; do
    if have "$c"; then printf '  %s  %-8s %s\n' "${GREEN}✓${RESET}" "$c" "$(command -v "$c")"
    else printf '  %s  %-8s %s\n' "${YELLOW}·${RESET}" "$c" "${DIM}$(lc 'not found' '未安装')${RESET}"; fi
  done
  printf '\n%s\n' "${BOLD}$(lc 'installed agents' '已安装 agent')${RESET}"
  cmd_list
  printf '%s\n' "${BOLD}$(lc 'config files' '配置文件')${RESET}"
  local f
  for f in "$HOME/.pi/agent/models.json" "$HOME/.omo/agent/models.json" \
           "$HOME/.omp/agent/models.yml" "$HOME/.omp/agent/config.yml" \
           "${CLAUDE_CONFIG_DIR:-$HOME/.claude}/settings.json" "$HOME/.codex/config.toml" \
           "$HOME/.grok/config.toml" "${XDG_CONFIG_HOME:-$HOME/.config}/opencode/opencode.json"; do
    if [ -f "$f" ]; then printf '  %s  %s\n' "${GREEN}✓${RESET}" "$f"
    else printf '  %s  %s\n' "${YELLOW}·${RESET}" "$f"; fi
  done
  printf '\n'
}

usage() {
  cat <<EOF
${BOLD}$NAME $VERSION${RESET} — $(lc 'one-shot installer + configurator for AI CLI agents' 'AI CLI agent 一键安装 + 配置（全自研，无上游依赖）')

${BOLD}$(lc 'USAGE' '用法')${RESET}
  $NAME                                    $(lc 'interactive: language → agents → install → configure' '交互：语言 → agent → 安装 → 配置')
  $NAME <agent>[,agent...] [options]       $(lc 'direct: pi opencode pi,claude all ...' '直接指定：pi / opencode / pi,claude / all')
  $NAME list | doctor | help

${BOLD}$(lc 'AGENTS' 'agent')${RESET}
  pi          Pi                https://pi.dev            npm/@earendil-works/pi-coding-agent
  omo         OmO               https://omo.dev           get.omo.dev/install.sh
  omp         OMP               https://omp.sh            omp.sh/install（回退 bun/npm）
  claude      Claude Code       claude.com                claude.ai/install.sh（仅 Linux/WSL）
  codex       Codex CLI         openai/codex              npm/@openai/codex
  grok        Grok Build        x.ai/cli                  x.ai/cli/install.sh
  opencode    OpenCode          opencode.ai               opencode.ai/install

${BOLD}$(lc 'OPTIONS' '选项')${RESET}
  -y, --yes              $(lc 'non-interactive' '非交互模式')
      --cn               $(lc 'force CN acceleration (npm/node mirrors + GitHub proxy)' '强制开启国内加速（npm / Node 镜像 + GitHub 反代）')
      --no-cn            $(lc 'disable acceleration; use official sources' '关闭加速，全程使用官方源')
      --proxy URL        $(lc 'HTTP proxy for curl, e.g. http://127.0.0.1:7890' '给 curl 用的代理，如 http://127.0.0.1:7890')
      --base-url URL     $(lc 'API endpoint base URL' '接口 base URL')
      --api-key KEY      $(lc 'API key (masked input: first3+***+last3)' 'API key（掩码输入：前3+***+后3）')
      --models a,b,c     $(lc 'model ids to register (pi/omo/omp/opencode)' '注册的模型 id（pi/omo/omp/opencode）')
      --model ID         $(lc 'default model (claude/codex/grok/omp/opencode)' '默认模型（claude/codex/grok/omp/opencode）')
      --skip-install     $(lc 'configure only' '只配置，不安装')
      --dry-run          $(lc 'print plan only' '只打印计划')
      --fail-fast        $(lc 'stop at first failure' '首败即停')
      --assume-tty       $(lc 'treat stdin as interactive (containers/CI)' '把 stdin 当交互输入（容器/CI）')
  -l, --lang en|zh       $(lc 'language (skips prompt)' '语言（跳过选择）')
  -h, --help             $(lc 'this help' '帮助')
  -V, --version          $(lc 'version' '版本')

${BOLD}$(lc 'ENVIRONMENT' '环境变量')${RESET}
  AICLI_BASE_URL AICLI_API_KEY AICLI_MODELS AICLI_MODEL AICLI_LANG
  AICLI_ASSUME_TTY GROK_ALIAS GROK_CONTEXT_WINDOW CODEX_WIRE_API
  AICLI_OPENCODE_V2   (1 = force opencode v2 config format)

${BOLD}$(lc 'CN ACCELERATION' '国内加速')${RESET}
  AICLI_CN            auto|1|0 $(lc '(default auto: enable on CN network)' '（默认 auto：国内网络自动启用）')
  AICLI_PROXY         $(lc 'e.g. http://127.0.0.1:7890' '例如 http://127.0.0.1:7890')
  AICLI_NPM_REGISTRY  $(lc 'default https://registry.npmmirror.com/' '默认 https://registry.npmmirror.com/')
  AICLI_NODE_MIRROR   $(lc 'default https://npmmirror.com/mirrors/node' '默认 https://npmmirror.com/mirrors/node')
  AICLI_GH_PROXY      $(lc 'default auto (benchmarked); set a prefix to force, "none" to disable' '默认 auto（自动测速）；可指定反代前缀，或 none 关闭')
  $NAME cn           $(lc 'show the detected acceleration plan' '查看加速检测结果')
  $(lc 'In mainland China, download this script via CDN first (acceleration only applies after bash starts):' '中国大陆请先用 CDN 下载本脚本（加速在 bash 启动后才生效）：')
    curl -fsSL https://cdn.jsdelivr.net/gh/zxfccmm4/ai-cli-setup@main/ai-cli-setup.sh | bash -s -- --cn

${BOLD}$(lc 'CONFIG FILES' '配置文件')${RESET}
  pi       ~/.pi/agent/{models,settings}.json
  omo      ~/.omo/agent/{models,settings}.json
  omp      ~/.omp/agent/{models.yml,config.yml}
  claude   ~/.claude/settings.json (env: ANTHROPIC_BASE_URL/AUTH_TOKEN/MODEL)
  codex    ~/.codex/{config.toml,auth.json}
  grok     ~/.grok/config.toml
  opencode ~/.config/opencode/opencode.json

${BOLD}$(lc 'EXAMPLES' '示例')${RESET}
  $NAME                          $(lc 'interactive wizard' '交互向导')
  $NAME pi,opencode              $(lc 'two agents' '两个 agent')
  $NAME all -y --base-url https://gw.example.com/v1 --api-key sk-xxx --models m1,m2
EOF
}

# ============================================================
# 14. 参数解析 / 主流程
# ============================================================
parse_args() {
  while [ $# -gt 0 ]; do
    case "$1" in
      -y|--yes) NON_INTERACTIVE=1; shift ;;
      --skip-install) SKIP_INSTALL=1; shift ;;
      --dry-run) DRY_RUN=1; shift ;;
      --fail-fast) FAIL_FAST=1; shift ;;
      --assume-tty) ASSUME_TTY=1; shift ;;
      -l|--lang) LANG_CODE="$(normalize_lang "${2:-en}")"; LANG_EXPLICIT=1; shift 2 ;;
      --cn) AICLI_CN=1; shift ;;
      --no-cn) AICLI_CN=0; shift ;;
      --proxy) PROXY="$2"; export AICLI_PROXY="$2"; shift 2 ;;
      cn) COMMAND="$1"; shift ;;
      --base-url) BASE_URL="$2"; shift 2 ;;
      --api-key) API_KEY="$2"; shift 2 ;;
      --models) MODELS="$2"; shift 2 ;;
      --model) MODEL="$2"; shift 2 ;;
      --grok-alias) GROK_ALIAS="$2"; shift 2 ;;
      -h|--help) usage; exit 0 ;;
      -V|--version) printf '%s %s\n' "$NAME" "$VERSION"; exit 0 ;;
      list|doctor|help) COMMAND="$1"; shift ;;
      all) SELECTED="$(printf '%s' "$ALL_AGENTS" | tr ' ' ',')"; shift ;;
      pi|omo|omp|claude|codex|grok|opencode)
        if [ -n "$SELECTED" ]; then SELECTED="$SELECTED,$1"; else SELECTED="$1"; fi; shift ;;
      *,*)
        local parts p ok=1
        parts="$(printf '%s' "$1" | tr ',' ' ')"
        for p in $parts; do agent_valid "$p" || { ok=0; break; }; done
        [ "$ok" -eq 1 ] || die "$(lc "unknown agent: $1" "未知 agent：$1")"
        SELECTED="${SELECTED:+$SELECTED,}$1"; shift ;;
      -*) die "$(lc "unknown option: $1" "未知选项：$1")" ;;
      *) die "$(lc "unknown: $1" "未知：$1")" ;;
    esac
  done
}

COMMAND=""

main() {
  parse_args "$@"

  case "$COMMAND" in
    help) usage; exit 0 ;;
    list) cmd_list; exit 0 ;;
    doctor) cmd_doctor; exit 0 ;;
    cn) cn_init; cn_selftest_out; exit 0 ;;
  esac

  printf '\n%s\n' "${BOLD}$NAME $VERSION${RESET} — $(lc 'AI agent installer + configurator' 'AI agent 安装 + 配置')${RESET}" >&2

  # 把“上次装过但当前 shell 还没 source rc”的目录先加进 PATH：否则 have <bin>
  # 判定为未安装，会重复下载/重装（独立 Node 尤其明显，一次 50MB）。
  local d
  for d in "$HOME/.local/bin" "$(node_standalone_bin_dir)" "$HOME/.grok/bin" "$HOME/.bun/bin" "$HOME/.opencode/bin"; do
    case ":$PATH:" in *":$d:"*) continue ;; esac
    [ -d "$d" ] || continue
    PATH="$d:$PATH"
  done
  export PATH
  hash -r 2>/dev/null || true

  if interactive_run; then prompt_language; fi
  cn_init   # 国内加速：探测网络 / 代理，设置 npm 镜像与 Node、GitHub 反代

  # 选 agent
  if [ -z "$SELECTED" ]; then
    if interactive_run; then prompt_agents
    else SELECTED="$(printf '%s' "$ALL_AGENTS" | tr ' ' ',')"; fi
  fi

  local total_start total_end total_elapsed
  total_start="$(date +%s)"

  # --- 阶段 1：安装 ---
  step "$(lc '[1/3] Install AI agents' '[1/3] 安装 AI agent')"
  local a rc=0 okc=0 failc=0 t0 t1 t_inst t_conf
  local -a results=()

  for a in $(printf '%s' "$SELECTED" | tr ',' ' '); do
    if agent_linux_only "$a" && [ "$OS" != "linux" ]; then
      warn "$(lc "$(agent_title "$a") is Linux/WSL only; skipping install" "$(agent_title "$a") 仅支持 Linux/WSL；跳过安装")"
      eval "time_inst_${a}=0"
      eval "status_inst_${a}=SKIP"
      eval "skip_note_${a}=\"$(lc 'Linux/WSL only' '仅 Linux/WSL')\""
      continue
    fi
    if agent_unrunnable_here "$a"; then
      warn "$(lc "$(agent_title "$a") needs Node.js, which cannot run on this musl system (OpenWrt/iStoreOS); skipping install" "$(agent_title "$a") 依赖 Node.js，本 musl 系统（OpenWrt/iStoreOS）无法直接运行；跳过安装")"
      info "$(lc "run it in a Debian/Alpine container instead, or install a musl Node.js first" "请改用 Debian/Alpine 容器运行，或先自行安装 musl 版 Node.js")"
      eval "time_inst_${a}=0"
      eval "status_inst_${a}=SKIP"
      eval "skip_note_${a}=\"$(lc 'needs Node.js (musl)' '需 Node.js（musl）')\""
      continue
    fi
    t0="$(date +%s)"
    rc=0; install_agent "$a" || rc=$?
    t1="$(date +%s)"
    eval "time_inst_${a}=$((t1 - t0))"
    if [ "$rc" -eq 0 ]; then
      eval "status_inst_${a}=OK"
    else
      eval "status_inst_${a}=FAIL"
      failc=$((failc + 1))
      results+=("FAIL|$a|install")
      [ "$FAIL_FAST" -eq 1 ] && { warn "$(lc 'fail-fast: stopping' 'fail-fast：停止')"; break; }
    fi
  done

  # --- 阶段 2：统一收集凭据 ---
  step "$(lc '[2/3] Credentials (asked once, shared by all agents)' '[2/3] 凭据（只问一次，所有 agent 共用）')"
  collect_credentials

  # --- 阶段 3：批量配置 ---
  step "$(lc '[3/3] Generate native configurations' '[3/3] 批量写入原生配置')"
  for a in $(printf '%s' "$SELECTED" | tr ',' ' '); do
    local s_inst; eval "s_inst=\${status_inst_${a}:-OK}"
    if [ "$s_inst" = "FAIL" ]; then
      continue
    fi
    t0="$(date +%s)"
    rc=0; configure_agent "$a" || rc=$?
    t1="$(date +%s)"
    t_conf=$((t1 - t0))
    eval "t_inst=\${time_inst_${a}:-0}"
    local total_agent=$((t_inst + t_conf))
    if [ "$rc" -eq 0 ]; then
      okc=$((okc + 1))
      if [ "$s_inst" = "SKIP" ]; then
        results+=("SKIP|$a|${total_agent}s")
      else
        results+=("OK|$a|${total_agent}s")
      fi
    else
      failc=$((failc + 1))
      results+=("FAIL|$a|config")
      [ "$FAIL_FAST" -eq 1 ] && break
    fi
  done

  total_end="$(date +%s)"
  total_elapsed=$((total_end - total_start))

  # --- 汇总 ---
  printf '\n%s\n' "${BOLD}$(lc 'Summary' '汇总')${RESET}" >&2
  printf '%s\n' "${DIM}────────────────────────────────────────────${RESET}" >&2
  local r st a2 note
  for r in ${results[@]+"${results[@]}"}; do
    st="${r%%|*}"; r="${r#*|}"; a2="${r%%|*}"; note="${r##*|}"
    if [ "$st" = "OK" ]; then
      printf '  %s  %-12s %s\n' "${GREEN}✓${RESET}" "$(agent_title "$a2")" "${DIM}$note${RESET}" >&2
    elif [ "$st" = "SKIP" ]; then
      local snote; eval "snote=\${skip_note_${a2}:-}"
      printf '  %s  %-12s %s\n' "${YELLOW}-${RESET}" "$(agent_title "$a2")" "${DIM}$note${snote:+ · $snote} ($(lc 'config only' '仅写配置'))${RESET}" >&2
    else
      printf '  %s  %-12s %s\n' "${RED}✗${RESET}" "$(agent_title "$a2")" "${RED}$(lc "$note failed" "$note 失败")${RESET}" >&2
    fi
  done
  printf '%s\n' "${DIM}────────────────────────────────────────────${RESET}" >&2
  info "$(lc "$okc configured, $failc failed (total: ${total_elapsed}s)" "配置成功 $okc 个，失败 $failc 个（总耗时 ${total_elapsed}s）")"
  [ "$failc" -eq 0 ]
}

main "$@"
