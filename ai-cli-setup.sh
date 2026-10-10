#!/usr/bin/env bash
#
# ai-cli-setup.sh — 把 zxfccmm4 的 AI CLI 一键安装脚本整合成一个入口。
# ai-cli-setup.sh — one entry point for zxfccmm4's AI CLI one-click installers.
#
# 整合的上游仓库 / integrated upstream repositories:
#   pi      -> zxfccmm4/pi-setup                  安装并配置 Pi            (pi.dev)
#   omo     -> zxfccmm4/omo-setup                 安装并配置 OmO           (omo.dev)
#   claude  -> zxfccmm4/claude-code-linux-installer  安装并配置 Claude Code
#   codex   -> zxfccmm4/deploy-codex              安装并配置 Codex CLI
#   grok    -> zxfccmm4/GrokBuild                 安装 Grok Build + 写入 ~/.grok/config.toml
#
# 本脚本不修改任何上游代码：它只负责
#   1) 选择工具 (单个 / 多个 / 全部)
#   2) 把 base_url / api_key / 模型 等凭据「问一次，喂给所有工具」
#   3) 下载上游脚本到缓存 (raw.githubusercontent.com，失败自动切 jsDelivr)
#   4) 逐个执行、互不影响，最后给出汇总报告
#
# 远程用法 / remote usage:
#   curl -fsSL https://raw.githubusercontent.com/zxfccmm4/ai-cli-setup/main/ai-cli-setup.sh | bash -s -- all
#   curl -fsSL .../ai-cli-setup.sh | bash -s -- claude -y --base-url URL --api-key KEY
#
# 本地用法 / local usage:
#   ./ai-cli-setup.sh                 # 交互选择
#   ./ai-cli-setup.sh all             # 全部（凭据问一次）
#   ./ai-cli-setup.sh pi -y --base-url URL --api-key KEY --models a,b
#   ./ai-cli-setup.sh codex -- --restore      # "--" 之后的参数原样透传给上游
#   ./ai-cli-setup.sh list
#   ./ai-cli-setup.sh doctor
#   ./ai-cli-setup.sh download all
#
# 许可 / license: MIT（本脚本）。上游各自保留其许可（均为 MIT）。
#
set -Eeuo pipefail

AICLI_VERSION="1.0.0"
AICLI_NAME="ai-cli-setup"

# ---------------------------------------------------------------------------
# 0. 确保在 bash 下运行
# ---------------------------------------------------------------------------
if [ -z "${BASH_VERSION:-}" ]; then
  exec bash "$0" "$@"
fi

# ---------------------------------------------------------------------------
# 1. 全局默认值
# ---------------------------------------------------------------------------
SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" 2>/dev/null && pwd || echo "$PWD")"

# 上游 git ref：默认 main；--pin 时使用下面经过验证的提交
UPSTREAM_REF="${AICLI_REF:-main}"
USE_PINNED=0

# 下载根地址（可覆盖，便于内网镜像）
RAW_HOST="${AICLI_RAW_HOST:-https://raw.githubusercontent.com}"
JSD_HOST="${AICLI_JSD_HOST:-https://cdn.jsdelivr.net/gh}"
REPO_OWNER="${AICLI_OWNER:-zxfccmm4}"

CACHE_BASE="${AICLI_CACHE_DIR:-${XDG_CACHE_HOME:-$HOME/.cache}/ai-cli-setup}"
USE_CACHE=1
REFRESH=0

LANG_CODE="${AICLI_LANG:-}"
FORCE_INTERACTIVE=0
NON_INTERACTIVE=0
DELEGATE=0
DRY_RUN=0
SKIP_INSTALL=0
FAIL_FAST=0

BASE_URL="${AICLI_BASE_URL:-}"
API_KEY="${AICLI_API_KEY:-}"
MODELS="${AICLI_MODELS:-}"
MODEL="${AICLI_MODEL:-}"
GROK_ALIAS="${AICLI_GROK_ALIAS:-Steve}"
GROK_SEARCH="${AICLI_GROK_SEARCH:-}"     # on|off，空=交互时询问 / 非交互默认 off
GROK_CONTEXT_WINDOW="${AICLI_GROK_CONTEXT_WINDOW:-500000}"

ONLY=""
SKIP=""
PASSTHROUGH=()          # "--" 之后原样转发给上游
SELECTED=()             # 位置参数里列出的工具
COMMAND=""

# 已验证的上游提交（--pin 时使用，保证可复现）
PIN_claude="7b944386a3e43d2c364e2abb202385a688476789"
PIN_pi="caa0aaac6f1c07ae77e74210d97e814e78e065cd"
PIN_omo="1e10043c8b0437d76cd565ea10cefcf5837f211e"
PIN_grok="287232842a9ad989a2f8050a935be881fe4f6d4a"
PIN_codex="3fd91ce6e364720383edbff3899e6578b4835384"

# ---------------------------------------------------------------------------
# 2. 语言 / i18n
# ---------------------------------------------------------------------------
normalize_lang() {
  case "$1" in
    zh|zh-*|zh_*|*[_-]CN|*[_-]CN.*|*[_-]TW|*[_-]TW.*|*[_-]HK|*[_-]HK.*) printf 'zh' ;;
    *) printf 'en' ;;
  esac
}

if [ -n "$LANG_CODE" ]; then
  LANG_CODE="$(normalize_lang "$LANG_CODE")"
else
  LANG_CODE="$(normalize_lang "${LC_ALL:-${LC_MESSAGES:-${LANG:-}}}")"
fi

# lc 'english' '中文'
lc() { if [ "$LANG_CODE" = "zh" ]; then printf '%s' "$2"; else printf '%s' "$1"; fi; }

# ---------------------------------------------------------------------------
# 3. 输出helper
# ---------------------------------------------------------------------------
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

# ---------------------------------------------------------------------------
# 4. TTY / 交互
# ---------------------------------------------------------------------------
have_tty() {
  [ -t 0 ] && return 0
  { exec 9<>/dev/tty; } 2>/dev/null || return 1
  exec 9>&- 9<&- 2>/dev/null || true
  return 0
}

# read_tty <变量名> <提示语> <是否隐藏 0|1>
read_tty() {
  local __var="$1" __prompt="$2" __secret="${3:-0}" __ans=""
  if [ ! -t 0 ]; then
    # 管道模式：脚本已读完 stdin，只能走 /dev/tty
    printf '%s' "${__prompt}" > /dev/tty
  else
    printf '%s' "${__prompt}"
  fi
  if [ "$__secret" -eq 1 ]; then
    if [ -t 0 ]; then IFS= read -r -s __ans || true; printf '\n'
    else IFS= read -r -s __ans < /dev/tty || true; printf '\n' > /dev/tty; fi
  else
    if [ -t 0 ]; then IFS= read -r __ans || true
    else IFS= read -r __ans < /dev/tty || true; fi
  fi
  printf -v "$__var" '%s' "$__ans"
}

# ask <变量名> <提示语> <默认值> <是否隐藏>
ask() {
  local __var="$1" __prompt="$2" __def="${3:-}" __secret="${4:-0}" __val=""
  read_tty __val "${__prompt}${__def:+ ${DIM}[${__def}]${RESET}} " "$__secret"
  [ -n "$__val" ] || __val="$__def"
  printf -v "$__var" '%s' "$__val"
}

confirm() {
  local __prompt="${1:-$(lc 'Continue?' '继续？')}" __def="${2:-n}" __ans=""
  [ "$NON_INTERACTIVE" -eq 1 ] && return 0
  have_tty || return 0
  if [ "$__def" = "y" ]; then
    read_tty __ans "${__prompt} ${DIM}[Y/n]${RESET} " 0
    case "$__ans" in ""|[yY]|[yY][eE][sS]) return 0 ;; *) return 1 ;; esac
  fi
  read_tty __ans "${__prompt} ${DIM}[y/N]${RESET} " 0
  case "$__ans" in [yY]|[yY][eE][sS]) return 0 ;; *) return 1 ;; esac
}

mask_secret() {
  local s="${1:-}"
  if [ -z "$s" ]; then printf '%s' "$(lc '(empty)' '（空）')"
  elif [ ${#s} -le 8 ]; then printf '****'
  else printf '%s****%s' "${s:0:4}" "${s: -4}"; fi
}

mask_url() {
  local u="${1:-}"
  case "$u" in
    *://*:*@*) printf '%s' "$(printf '%s' "$u" | sed -E 's#(://[^/@:]+):[^/@]+@#\1:***@#')" ;;
    *) printf '%s' "$u" ;;
  esac
}

# ---------------------------------------------------------------------------
# 5. 平台
# ---------------------------------------------------------------------------
OS=""; ARCH=""
detect_platform() {
  case "$(uname -s)" in
    Darwin) OS=macos ;;
    Linux)  OS=linux ;;
    *)      OS="$(uname -s | tr '[:upper:]' '[:lower:]')" ;;
  esac
  case "$(uname -m)" in
    x86_64|amd64) ARCH=x86_64 ;;
    arm64|aarch64) ARCH=arm64 ;;
    *) ARCH="$(uname -m)" ;;
  esac
}
detect_platform

is_root() { [ "$(id -u)" -eq 0 ]; }

# ---------------------------------------------------------------------------
# 6. 工具清单（manifest）
# ---------------------------------------------------------------------------
ALL_TOOLS="pi omo claude codex grok opencode"

# opencode 不是 zxfccmm4 的仓库：本脚本自己实现安装与配置（官方 installer + opencode.json）
OPENCODE_INSTALL_URL="${AICLI_OPENCODE_INSTALL_URL:-https://opencode.ai/install}"
OPENCODE_NPM_PKG="${AICLI_OPENCODE_NPM_PKG:-opencode-ai}"
OPENCODE_PROVIDER="${AICLI_OPENCODE_PROVIDER:-}"
OPENCODE_PROVIDER_NAME="${AICLI_OPENCODE_PROVIDER_NAME:-}"
OPENCODE_NPM="${AICLI_OPENCODE_NPM:-@ai-sdk/openai-compatible}"
OPENCODE_CONFIG="${AICLI_OPENCODE_CONFIG:-${XDG_CONFIG_HOME:-$HOME/.config}/opencode/opencode.json}"
OPENCODE_METHOD="${AICLI_OPENCODE_METHOD:-}"   # official | npm

# 已内建了 OpenAI 兼容 provider 的知名网关域名（用它们自己的 provider id，否则用 openai-compatible）
opencode_known_provider() {
  local url
  url="$(printf '%s' "$1" | tr '[:upper:]' '[:lower:]')"
  case "$url" in
    *openrouter.ai*) printf 'openrouter|OpenRouter|' ;;
    *api.deepseek.com*) printf 'deepseek|DeepSeek|@ai-sdk/openai-compatible' ;;
    *api.openai.com*) printf 'openai|OpenAI|' ;;
    *generativelanguage.googleapis.com*) printf 'google|Google|' ;;
    *open.bigmodel.cn*) printf 'zhipuglm|智谱 GLM|@ai-sdk/openai-compatible' ;;
    *) return 1 ;;
  esac
}

tool_repo() {
  case "$1" in
    pi)     printf 'pi-setup' ;;
    omo)    printf 'omo-setup' ;;
    claude) printf 'claude-code-linux-installer' ;;
    codex)  printf 'deploy-codex' ;;
    grok)   printf 'GrokBuild' ;;
    opencode) return 1 ;;   # 无上游仓库
    *)      return 1 ;;
  esac
}

tool_pin() {
  case "$1" in
    pi)     printf '%s' "$PIN_pi" ;;
    omo)    printf '%s' "$PIN_omo" ;;
    claude) printf '%s' "$PIN_claude" ;;
    codex)  printf '%s' "$PIN_codex" ;;
    grok)   printf '%s' "$PIN_grok" ;;
    opencode) printf '%s' "${AICLI_OPENCODE_REF:-latest}" ;;
    *)      return 1 ;;
  esac
}

# 需要下载的文件（每行一个，相对仓库根）
tool_files() {
  case "$1" in
    pi)     printf '%s\n' pi-setup.sh pi-config.mjs ;;
    omo)    printf '%s\n' omo-setup.sh omo-config.mjs ;;
    claude) printf '%s\n' install-claude-code.sh ;;
    codex)  printf '%s\n' deploy-codex.sh ;;
    grok)   printf '%s\n' bootstrap.sh install-config.sh config.toml ;;
    opencode) return 1 ;;   # 无上游文件：官方 installer 自取
    *)      return 1 ;;
  esac
}

# 入口脚本（相对仓库根）
tool_entry() {
  case "$1" in
    pi)     printf 'pi-setup.sh' ;;
    omo)    printf 'omo-setup.sh' ;;
    claude) printf 'install-claude-code.sh' ;;
    codex)  printf 'deploy-codex.sh' ;;
    grok)   printf 'bootstrap.sh' ;;
    opencode) return 1 ;;
    *)      return 1 ;;
  esac
}

tool_title() {
  case "$1" in
    pi)     printf 'Pi' ;;
    omo)    printf 'OmO' ;;
    claude) printf 'Claude Code' ;;
    codex)  printf 'Codex CLI' ;;
    grok)   printf 'Grok Build' ;;
    opencode) printf 'OpenCode' ;;
    *)      printf '%s' "$1" ;;
  esac
}

tool_homepage() {
  case "$1" in
    pi)     printf 'https://pi.dev' ;;
    omo)    printf 'https://omo.dev' ;;
    claude) printf 'https://claude.ai/code' ;;
    codex)  printf 'https://github.com/openai/codex' ;;
    grok)   printf 'https://x.ai/cli' ;;
    opencode) printf 'https://opencode.ai' ;;
    *)      printf '-' ;;
  esac
}

# 该工具是否支持在 Linux 上安装到 /usr（需要 root）
tool_needs_root() {
  case "$1" in
    codex) [ "$OS" = "linux" ] && return 0; return 1 ;;
    *)     return 1 ;;
  esac
}

# 上游是否支持 --lang
tool_supports_lang() {
  case "$1" in pi|omo|claude) return 0 ;; *) return 1 ;; esac
}

# 上游是否支持 --dry-run
tool_supports_dry_run() {
  case "$1" in pi|omo|claude|codex|opencode) return 0 ;; *) return 1 ;; esac
}

# 是否为「自实现」工具（没有上游仓库）
tool_selfmanaged() {
  case "$1" in opencode) return 0 ;; *) return 1 ;; esac
}

tool_valid() {
  case "$1" in pi|omo|claude|codex|grok|opencode) return 0 ;; *) return 1 ;; esac
}

# 展开 "a,b" 形式的工具列表
expand_tools() {
  local spec="$1" t out=""
  local IFS=','
  for t in $spec; do
    t="$(printf '%s' "$t" | tr -d '[:space:]')"
    [ -n "$t" ] || continue
    tool_valid "$t" || die "$(lc "unknown tool: $t" "未知工具：$t")"
    out="$out $t"
  done
  printf '%s' "$out"
}

# ---------------------------------------------------------------------------
# 7. 下载 / 缓存
# ---------------------------------------------------------------------------
download_cmd() {
  if command -v curl >/dev/null 2>&1; then printf 'curl'
  elif command -v wget >/dev/null 2>&1; then printf 'wget'
  else return 1; fi
}

# fetch_url <url> <dest>  -> 0/1
fetch_url() {
  local url="$1" dest="$2" dc
  dc="$(download_cmd)" || die "$(lc 'need curl or wget' '需要 curl 或 wget')"
  rm -f "$dest" 2>/dev/null || true
  if [ "$dc" = "curl" ]; then
    curl -fsSL --connect-timeout 10 --max-time 180 -o "$dest" "$url" 2>/dev/null || return 1
  else
    wget -q --timeout=180 -O "$dest" "$url" 2>/dev/null || return 1
  fi
  [ -s "$dest" ] || return 1
  # 明确的 404 页面
  if head -c 200 "$dest" 2>/dev/null | grep -q '^404: Not Found'; then rm -f "$dest"; return 1; fi
  return 0
}

ref_for() {
  if [ "$USE_PINNED" -eq 1 ]; then tool_pin "$1"; else printf '%s' "$UPSTREAM_REF"; fi
}

cache_dir_for() {
  local tool="$1" repo ref
  repo="$(tool_repo "$tool")"
  ref="$(ref_for "$tool")"
  printf '%s/%s@%s' "$CACHE_BASE" "$repo" "$ref"
}

# 本地仓库布局优先：<dir>/upstream/<repo>/<file> 或 <dir>/<file>
# 命中则打印该目录（其下所有必需文件都在）
local_dir_for() {
  local tool="$1" repo cand file ok
  repo="$(tool_repo "$tool")" || return 1
  for cand in "$SCRIPT_DIR/upstream/$repo" "$SCRIPT_DIR"; do
    [ -d "$cand" ] || continue
    ok=1
    for file in $(tool_files "$tool"); do
      [ -s "$cand/$file" ] || { ok=0; break; }
    done
    if [ "$ok" -eq 1 ]; then printf '%s' "$cand"; return 0; fi
  done
  return 1
}

# ensure_tool <tool> -> 打印本地目录；失败返回 1
ensure_tool() {
  local tool="$1" repo ref dir file dest url ok rc=0 localdir
  repo="$(tool_repo "$tool")" || return 1
  ref="$(ref_for "$tool")"
  dir="$(cache_dir_for "$tool")"

  # 1) 本地文件优先（仓库内 upstream/<repo>/ 已放好全部文件时直接用）
  if localdir="$(local_dir_for "$tool")"; then
    printf '%s' "$localdir"; return 0
  fi

  # 2) 缓存命中
  if [ "$USE_CACHE" -eq 1 ] && [ "$REFRESH" -eq 0 ]; then
    ok=1
    for file in $(tool_files "$tool"); do
      [ -s "$dir/$file" ] || { ok=0; break; }
    done
    if [ "$ok" -eq 1 ]; then printf '%s' "$dir"; return 0; fi
  fi

  # 3) 下载
  mkdir -p "$dir" || return 1
  info "$(lc "downloading $repo@$ref" "正在下载 $repo@$ref")" >&2
  for file in $(tool_files "$tool"); do
    dest="$dir/$file"
    if [ "$USE_CACHE" -eq 1 ] && [ "$REFRESH" -eq 0 ] && [ -s "$dest" ]; then continue; fi
    ok=0
    for url in "$RAW_HOST/$REPO_OWNER/$repo/$ref/$file" \
               "$JSD_HOST/$REPO_OWNER/$repo@$ref/$file"; do
      if fetch_url "$url" "$dest"; then ok=1; break; fi
    done
    if [ "$ok" -ne 1 ]; then
      err "$(lc "failed to download $file from $repo@$ref" "下载 $file 失败（$repo@$ref）")"
      return 1
    fi
    case "$file" in
      *.sh) chmod +x "$dest" 2>/dev/null || true ;;
    esac
  done
  printf '%s' "$dir"
  return 0
}

# ---------------------------------------------------------------------------
# 8. 模型列表：从 <base_url>/v1/models 拉取
# ---------------------------------------------------------------------------
json_model_ids() {
  if command -v jq >/dev/null 2>&1; then
    jq -r '((.data // .models // [])[] | (.id // .name // .slug // empty))' 2>/dev/null
  elif command -v python3 >/dev/null 2>&1; then
    python3 -c '
import json,sys
try: d=json.load(sys.stdin)
except Exception: sys.exit(0)
items = d.get("data") or d.get("models") or []
if isinstance(items, dict): items = list(items.values())
for it in items:
    if isinstance(it, str): print(it); continue
    if not isinstance(it, dict): continue
    v = it.get("id") or it.get("name") or it.get("slug")
    if v: print(v)
' 2>/dev/null
  elif command -v node >/dev/null 2>&1; then
    node -e '
let s="";process.stdin.on("data",d=>s+=d).on("end",()=>{
try{const d=JSON.parse(s);let it=d.data||d.models||[];if(!Array.isArray(it))it=Object.values(it);
for(const x of it){const v=typeof x==="string"?x:(x&&(x.id||x.name||x.slug));if(v)console.log(v);}}catch(e){}});
' 2>/dev/null
  fi
}

fetch_models() {
  local base="$1" url ids
  [ -n "$base" ] || return 1
  base="${base%/}"
  case "$base" in
    */v1) url="$base/models" ;;
    *)    url="$base/v1/models" ;;
  esac
  local tmp
  tmp="$(mktemp "${TMPDIR:-/tmp}/aicli-models.XXXXXX")" || return 1
  if ! fetch_url "$url" "$tmp"; then rm -f "$tmp"; return 1; fi
  ids="$(json_model_ids < "$tmp" | head -200 | paste -sd, - 2>/dev/null || true)"
  rm -f "$tmp"
  [ -n "$ids" ] || return 1
  printf '%s' "$ids"
}

# ---------------------------------------------------------------------------
# 9. 凭据收集（一次问清，喂给所有工具）
# ---------------------------------------------------------------------------
collect_credentials() {
  local need_models="$1"
  if [ -z "$BASE_URL" ]; then
    if [ "$NON_INTERACTIVE" -eq 1 ] || ! have_tty; then
      die "$(lc 'missing --base-url (required in non-interactive mode)' '缺少 --base-url（非交互模式必需）')"
    fi
    ask BASE_URL "$(lc 'API endpoint base URL (e.g. https://api.example.com/v1)' '接口 base URL（例：https://api.example.com/v1）')" ""
    [ -n "$BASE_URL" ] || die "$(lc 'base URL is required' 'base URL 必填')"
  fi
  if [ -z "$API_KEY" ]; then
    if [ "$NON_INTERACTIVE" -eq 1 ] || ! have_tty; then
      die "$(lc 'missing --api-key (required in non-interactive mode)' '缺少 --api-key（非交互模式必需）')"
    fi
    ask API_KEY "$(lc 'API key' 'API key')" "" 1
    [ -n "$API_KEY" ] || die "$(lc 'API key is required' 'API key 必填')"
  fi
  if [ "$need_models" -eq 1 ] && [ -z "$MODELS" ]; then
    info "$(lc 'fetching model list from the endpoint...' '正在从端点获取模型列表...')"
    local fetched=""
    fetched="$(fetch_models "$BASE_URL" || true)"
    if [ -n "$fetched" ]; then
      info "$(lc "found models: $fetched" "发现模型：$fetched")"
      if [ "$NON_INTERACTIVE" -eq 1 ] || ! have_tty; then
        MODELS="$fetched"
      else
        local ans=""
        ask ans "$(lc 'model ids to register (comma separated, blank = all above)' '要写入的模型 id（逗号分隔，留空 = 用上面的全部）')" "$fetched"
        MODELS="$ans"
      fi
    elif [ "$NON_INTERACTIVE" -eq 1 ] || ! have_tty; then
      warn "$(lc 'could not fetch models; pass --models a,b' '无法获取模型列表；请用 --models a,b 指定')"
    else
      ask MODELS "$(lc 'model ids (comma separated, required)' '模型 id（逗号分隔，必填）')" ""
    fi
  fi
  if [ -n "$MODEL" ] && [ -z "$MODELS" ]; then MODELS="$MODEL"; fi
}

# ---------------------------------------------------------------------------
# 10. GrokBuild：非交互写 ~/.grok/config.toml
# ---------------------------------------------------------------------------
toml_escape() {
  local s="${1:-}"
  s="${s//\\/\\\\}"; s="${s//\"/\\\"}"
  s="${s//$'\n'/\\n}"; s="${s//$'\r'/\\r}"; s="${s//$'\t'/\\t}"
  printf '%s' "$s"
}

write_grok_config() {
  local dir="$1"
  local alias="${2:-$GROK_ALIAS}"
  local model="${3:-${MODEL:-grok-4.7}}"
  local url="$4" key="$5" search="${6:-0}"
  local target_dir="${HOME}/.grok" target="${HOME}/.grok/config.toml"
  local tmp

  mkdir -p "$target_dir" || die "$(lc 'cannot create ~/.grok' '无法创建 ~/.grok')"

  if [ -f "$target" ]; then
    local bak
    bak="${target}.bak.$(date +%Y%m%d%H%M%S)"
    cp -p "$target" "$bak" && info "$(lc "backed up existing config to $bak" "已备份原配置到 $bak")"
  fi

  tmp="$(mktemp "${target_dir}/.config.toml.XXXXXX")" || die "$(lc 'mktemp failed' 'mktemp 失败')"
  chmod 600 "$tmp" 2>/dev/null || true

  {
    printf '[cli]\ninstaller = "internal"\n\n'
    printf '[models]\ndefault = "%s"\ndefault_reasoning_effort = "high"\n' "$(toml_escape "$alias")"
    [ "$search" = "1" ] && printf 'web_search = "%s"\n' "$(toml_escape "$alias")"
    printf '\n[model.%s]\n' "$alias"
    printf 'model = "%s"\n' "$(toml_escape "$model")"
    printf 'base_url = "%s"\n' "$(toml_escape "$url")"
    printf 'name = "%s"\n' "$(toml_escape "$model")"
    printf 'api_key = "%s"\n' "$(toml_escape "$key")"
    printf 'context_window = %s\n' "$GROK_CONTEXT_WINDOW"
    printf 'supports_reasoning_effort = true\n'
    printf 'reasoning_efforts = [\n    "low",\n    "medium",\n    "high",\n]\n'
    if [ "$search" = "1" ]; then
      printf 'api_backend = "responses"\n'
      printf 'supports_backend_search = true\n'
    fi
    printf '\n[features]\ntelemetry = false\nfeedback = false\n\n'
    printf '[telemetry]\ntrace_upload = false\nmixpanel_enabled = false\n\n'
    printf '[harness]\ndisable_codebase_upload = true\n\n'
    printf '[ui]\nmax_thoughts_width = 120\nfork_secondary_model = "grok-build"\n'
    printf 'yolo = false\ncompact_mode = false\npermission_mode = "always-approve"\n'
  } > "$tmp"

  if [ "$DRY_RUN" -eq 1 ]; then
    info "$(lc 'dry-run: would write' 'dry-run：将写入') $target"
    sed -E 's/^(api_key[[:space:]]*=[[:space:]]*).*/\1"***"/' "$tmp" | sed 's/^/    /' >&2
    rm -f "$tmp"
    return 0
  fi

  mv -f "$tmp" "$target"
  chmod 600 "$target" 2>/dev/null || true
  ok "$(lc "wrote $target" "已写入 $target")"
}

# ---------------------------------------------------------------------------
# 10b. OpenCode：安装 + 写 ~/.config/opencode/opencode.json
# ---------------------------------------------------------------------------
# 本脚本自实现（opencode 不属于 zxfccmm4 系列仓库）。
# 安装：官方 installer（https://opencode.ai/install），失败回退 npm -g opencode-ai。
# 配置：合并写入 opencode.json 的 provider/model，其他键（plugin / mcp / agent）保留。
run_opencode() {
  local rc=0

  # ---------- 1. 安装 / 更新 ----------
  if [ "$SKIP_INSTALL" -eq 1 ]; then
    info "$(lc '--skip-install: not touching the OpenCode binary' '--skip-install：不安装/更新 OpenCode 本体')"
  elif [ "$DRY_RUN" -eq 1 ]; then
    info "$(lc 'dry-run: would install/update OpenCode' 'dry-run：将安装/更新 OpenCode')"
  else
    local method="$OPENCODE_METHOD"
    if [ -z "$method" ]; then
      if command -v opencode >/dev/null 2>&1; then
        method="official"
      elif command -v npm >/dev/null 2>&1; then
        method="npm"
      else
        method="official"
      fi
    fi

    if [ "$method" = "npm" ]; then
      command -v npm >/dev/null 2>&1 || { err "$(lc 'npm not found' '未找到 npm')"; return 1; }
      info "$(lc "npm install -g $OPENCODE_NPM_PKG" "npm install -g $OPENCODE_NPM_PKG")"
      npm install -g "$OPENCODE_NPM_PKG" >&2 || { err "$(lc 'npm install failed' 'npm 安装失败')"; return 1; }
    else
      info "$(lc "running the official installer ($OPENCODE_INSTALL_URL)" "运行官方安装器（$OPENCODE_INSTALL_URL）")"
      if command -v curl >/dev/null 2>&1; then
        curl -fsSL "$OPENCODE_INSTALL_URL" | bash >&2 || rc=$?
      elif command -v wget >/dev/null 2>&1; then
        wget -qO- "$OPENCODE_INSTALL_URL" | bash >&2 || rc=$?
      else
        err "$(lc 'need curl or wget' '需要 curl 或 wget')"; return 1
      fi
      if [ "$rc" -ne 0 ]; then
        warn "$(lc 'official installer failed; falling back to npm' '官方安装器失败；回退到 npm')"
        if command -v npm >/dev/null 2>&1; then
          npm install -g "$OPENCODE_NPM_PKG" >&2 || { err "$(lc 'npm install failed' 'npm 安装失败')"; return 1; }
          rc=0
        else
          return 1
        fi
      fi
    fi
  fi

  # ---------- 2. 写配置 ----------
  if [ -z "$BASE_URL" ] || [ -z "$API_KEY" ]; then
    info "$(lc 'no credentials given; skipping opencode.json (run `opencode auth login` instead)' '未提供凭据；跳过 opencode.json（可改用 opencode auth login）')"
    return 0
  fi

  write_opencode_config
}

# 生成/合并 ~/.config/opencode/opencode.json
write_opencode_config() {
  local provider="$OPENCODE_PROVIDER"
  local name="$OPENCODE_PROVIDER_NAME"
  local npm="$OPENCODE_NPM"
  local known

  if [ -z "$provider" ]; then
    if known="$(opencode_known_provider "$BASE_URL")"; then
      provider="${known%%|*}"; name="${known#*|}"; npm="${name#*|}"; name="${name%%|*}"
    else
      # 未识别的网关：用自定义 provider id（由 host 推导），走 openai-compatible
      provider="$(printf '%s' "$BASE_URL" | sed -E 's#^https?://##; s#/.*$##; s#[^A-Za-z0-9]+#-#g')"
      [ -n "$provider" ] || provider="custom"
      name="$(printf '%s' "$BASE_URL" | sed -E 's#^https?://##; s#/.*$##')"
      [ -n "$npm" ] || npm="@ai-sdk/openai-compatible"
    fi
  fi

  # 模型列表：默认第一个作为默认模型
  local default_model="$MODEL"
  if [ -z "$default_model" ] && [ -n "$MODELS" ]; then
    default_model="$(printf '%s' "$MODELS" | cut -d, -f1 | tr -d '[:space:]')"
  fi

  if [ "$DRY_RUN" -eq 1 ]; then
    info "$(lc 'dry-run: would update' 'dry-run：将更新') $OPENCODE_CONFIG"
    printf '    provider : %s%s\n' "$provider" "${name:+ ($name)}" >&2
    printf '    baseURL  : %s\n' "$BASE_URL" >&2
    printf '    apiKey   : %s\n' "$(mask_secret "$API_KEY")" >&2
    printf '    models   : %s\n' "$MODELS" >&2
    [ -n "$default_model" ] && printf '    default  : %s/%s\n' "$provider" "$default_model" >&2
    return 0
  fi

  command -v node >/dev/null 2>&1 || { err "$(lc 'node is required to merge opencode.json' '合并 opencode.json 需要 node')"; return 1; }

  mkdir -p "$(dirname "$OPENCODE_CONFIG")" || return 1
  if [ -f "$OPENCODE_CONFIG" ]; then
    local bak
    bak="${OPENCODE_CONFIG}.bak.$(date +%Y%m%d%H%M%S)"
    cp -p "$OPENCODE_CONFIG" "$bak" && info "$(lc "backed up existing config to $bak" "已备份原配置到 $bak")"
  fi

  # shellcheck disable=SC2016
  KB_PROVIDER="$provider" KB_NAME="$name" KB_NPM="$npm" \
  KB_BASE_URL="$BASE_URL" KB_API_KEY="$API_KEY" KB_MODELS="$MODELS" KB_DEFAULT="$default_model" \
  node -e '
    const fs = require("fs");
    const file = process.argv[1];
    const env = process.env;
    let cfg = {};
    if (fs.existsSync(file)) {
      try { cfg = JSON.parse(fs.readFileSync(file, "utf8")); }
      catch (e) { console.error("warning: " + file + " is not plain JSON; regenerating"); }
    }
    if (!cfg || typeof cfg !== "object" || Array.isArray(cfg)) cfg = {};
    cfg.$schema = cfg.$schema || "https://opencode.ai/config.json";
    const id = env.KB_PROVIDER;
    cfg.provider = cfg.provider || {};
    const p = cfg.provider[id] = cfg.provider[id] || {};
    if (env.KB_NAME) p.name = env.KB_NAME;
    if (env.KB_NPM) p.npm = env.KB_NPM;
    p.options = Object.assign({}, p.options, { baseURL: env.KB_BASE_URL, apiKey: env.KB_API_KEY });
    const models = (env.KB_MODELS || "").split(",").map(s => s.trim()).filter(Boolean);
    if (models.length) {
      p.models = p.models || {};
      for (const m of models) {
        if (!p.models[m]) p.models[m] = { name: m.split("/").pop() };
      }
    }
    if (env.KB_DEFAULT) cfg.model = id + "/" + env.KB_DEFAULT;
    fs.writeFileSync(file, JSON.stringify(cfg, null, 2) + "\n", { mode: 0o600 });
    try { fs.chmodSync(file, 0o600); } catch (e) {}
  ' "$OPENCODE_CONFIG" || { err "$(lc 'failed to write opencode.json' '写入 opencode.json 失败')"; return 1; }

  ok "$(lc "wrote $OPENCODE_CONFIG" "已写入 $OPENCODE_CONFIG")"
  info "$(lc "provider: $provider   default model: ${default_model:-(unchanged)}" "provider：$provider   默认模型：${default_model:-（未改）}")"
}

# ---------------------------------------------------------------------------
# 11. 运行单个工具
# ---------------------------------------------------------------------------
# 为上游脚本构造环境变量（把统一凭据翻译成各家的变量名）
tool_env_prefix() {
  local tool="$1" out=""
  case "$tool" in
    pi)
      [ -n "$BASE_URL" ] && out="$out PISETUP_BASE_URL=$(printf '%q' "$BASE_URL")"
      [ -n "$API_KEY" ]  && out="$out PISETUP_API_KEY=$(printf '%q' "$API_KEY")"
      [ -n "$MODELS" ]   && out="$out PISETUP_MODELS=$(printf '%q' "$MODELS")"
      out="$out PISETUP_LANG=$(printf '%q' "$LANG_CODE")"
      ;;
    omo)
      [ -n "$BASE_URL" ] && out="$out OMO_BASE_URL=$(printf '%q' "$BASE_URL")"
      [ -n "$API_KEY" ]  && out="$out OMO_API_KEY=$(printf '%q' "$API_KEY")"
      [ -n "$MODELS" ]   && out="$out OMO_MODELS=$(printf '%q' "$MODELS")"
      out="$out OMO_LANG=$(printf '%q' "$LANG_CODE")"
      ;;
    claude)
      [ -n "$BASE_URL" ] && out="$out CLAUDE_BASE_URL=$(printf '%q' "$BASE_URL")"
      [ -n "$API_KEY" ]  && out="$out CLAUDE_API_KEY=$(printf '%q' "$API_KEY")"
      [ -n "$MODEL" ]    && out="$out CLAUDE_MODEL=$(printf '%q' "$MODEL")"
      out="$out CLAUDE_LANG=$(printf '%q' "$LANG_CODE")"
      ;;
    codex)
      [ -n "$BASE_URL" ] && out="$out CODEX_BASE_URL=$(printf '%q' "$BASE_URL")"
      [ -n "$API_KEY" ]  && out="$out CODEX_API_KEY=$(printf '%q' "$API_KEY")"
      [ -n "$MODEL" ]    && out="$out CODEX_MODEL=$(printf '%q' "$MODEL")"
      ;;
    grok)
      out="$out SKIP_GROK_SEARCH=$(printf '%q' "$([ "$GROK_SEARCH" = "on" ] && echo 0 || echo 1)")"
      ;;
  esac
  printf '%s' "$out"
}

# 上游额外参数
tool_extra_args() {
  local tool="$1" out=""
  if [ "$NON_INTERACTIVE" -eq 1 ]; then
    case "$tool" in
      claude) out="$out --non-interactive" ;;
    esac
  fi
  if [ "$FORCE_INTERACTIVE" -eq 1 ]; then
    case "$tool" in
      pi|omo) out="$out -i" ;;
    esac
  fi
  if [ "$SKIP_INSTALL" -eq 1 ]; then
    case "$tool" in
      pi|omo|claude) out="$out --skip-install" ;;
    esac
  fi
  if [ "$DRY_RUN" -eq 1 ] && tool_supports_dry_run "$tool"; then out="$out --dry-run"; fi
  if tool_supports_lang "$tool"; then out="$out --lang $LANG_CODE"; fi
  printf '%s' "$out"
}

# run_tool <tool> [extra args...] -> 返回上游退出码
run_tool() {
  local tool="$1"; shift
  local dir entry extra envs rc=0

  step "$(tool_title "$tool") — $(lc 'start' '开始')"

  # ---- OpenCode：本脚本自实现（无上游仓库） ----
  if tool_selfmanaged "$tool"; then
    run_opencode
    return $?
  fi

  dir="$(ensure_tool "$tool")" || { err "$(lc "$tool: download failed" "$tool：下载失败")"; return 1; }
  entry="$dir/$(tool_entry "$tool")"
  [ -f "$entry" ] || { err "$(lc "missing entry: $entry" "缺少入口脚本：$entry")"; return 1; }

  # ---- GrokBuild 特殊处理 ----
  if [ "$tool" = "grok" ]; then
    local search=0
    case "$GROK_SEARCH" in
      on|1|yes|true) search=1 ;;
      off|0|no|false) search=0 ;;
      *)
        if [ "$NON_INTERACTIVE" -eq 0 ] && have_tty; then
          confirm "$(lc 'enable server-side Search Tool (web_search/x_search)?' '开启服务端 Search Tool（web_search/x_search）？')" n && search=1 || search=0
        fi
        ;;
    esac

    # 1) 没有凭据（或显式 --delegate）：交给上游完整向导，体验最好
    if [ "$DELEGATE" -eq 1 ] || { [ "$NON_INTERACTIVE" -eq 0 ] && [ -z "$BASE_URL" ] && [ -z "$API_KEY" ]; }; then
      info "$(lc 'delegating to upstream GrokBuild wizard' '交给上游 GrokBuild 向导处理')"
      if [ "$SKIP_INSTALL" -eq 1 ]; then
        ( cd "$dir" && SKIP_GROK_CLI=1 bash "$entry" ) || rc=$?
        ( cd "$dir" && bash "$dir/install-config.sh" ) || rc=$?
      else
        ( cd "$dir" && bash "$entry" ) || rc=$?
      fi
      return $rc
    fi

    # 2) 受管模式：装 CLI（bootstrap，跳过配置），然后我们写配置
    if [ "$SKIP_INSTALL" -eq 0 ] && [ "$DRY_RUN" -eq 0 ]; then
      info "$(lc 'installing Grok Build CLI' '正在安装 Grok Build CLI')"
      ( cd "$dir" && SKIP_CONFIG=1 bash "$entry" ) || warn "$(lc 'Grok CLI install returned non-zero; continuing' 'Grok CLI 安装返回非 0；继续')"
    fi
    write_grok_config "$dir" "$GROK_ALIAS" "${MODEL:-grok-4.7}" "$BASE_URL" "$API_KEY" "$search"
    return 0
  fi

  # ---- 其余工具：统一走上游入口 ----
  extra="$(tool_extra_args "$tool")"
  envs="$(tool_env_prefix "$tool")"

  if [ "$DRY_RUN" -eq 1 ] && ! tool_supports_dry_run "$tool"; then
    warn "$(lc "$tool does not support --dry-run; skipping" "$tool 不支持 --dry-run；已跳过")"
    return 0
  fi

  # Linux 上 Codex 需要 root
  if tool_needs_root "$tool" && ! is_root; then
    if command -v sudo >/dev/null 2>&1; then
      if [ "$NON_INTERACTIVE" -eq 1 ] || confirm "$(lc "sudo is required to install $(tool_title "$tool") on Linux; continue?" "在 Linux 上安装 $(tool_title "$tool") 需要 sudo，继续？")" y; then
        info "$(lc 're-running with sudo' '使用 sudo 重新运行')"
        # shellcheck disable=SC2086
        ( cd "$dir" && eval "sudo env $envs bash \"$entry\" $extra \"\$@\"" ) || rc=$?
        return $rc
      fi
      warn "$(lc 'skipped' '已跳过')"
      return 1
    fi
    warn "$(lc "$tool needs root on Linux and sudo is unavailable" "$tool 在 Linux 上需要 root，但没有 sudo")"
    return 1
  fi

  info "$(lc "running $entry" "执行 $entry")"
  # shellcheck disable=SC2086
  ( cd "$dir" && eval "env $envs bash \"$entry\" $extra \"\$@\"" ) || rc=$?
  return $rc
}

# ---------------------------------------------------------------------------
# 12. 命令实现
# ---------------------------------------------------------------------------
resolve_selection() {
  local list="$1" t
  local out=()
  if [ -n "$ONLY" ]; then
    for t in $(expand_tools "$ONLY"); do out+=("$t"); done
  elif [ -n "$list" ]; then
    for t in $(expand_tools "$list"); do out+=("$t"); done
  else
    for t in $ALL_TOOLS; do out+=("$t"); done
  fi
  # 去掉 --skip
  if [ -n "$SKIP" ]; then
    local skipped
    skipped=" $(expand_tools "$SKIP") "
    local filtered=()
    for t in ${out[@]+"${out[@]}"}; do
      case "$skipped" in *" $t "*) continue ;; esac
      filtered+=("$t")
    done
    out=(${filtered[@]+"${filtered[@]}"})
  fi
  [ ${#out[@]} -gt 0 ] || die "$(lc 'no tool selected' '没有选择任何工具')"
  printf '%s\n' ${out[@]+"${out[@]}"}
}

cmd_run() {
  local tools
  tools="$(resolve_selection "$COMMAND_TOOLS")"
  local t rc=0 okc=0 failc=0
  local -a results=()

  # 多工具 / 受管模式：统一收集凭据
  local need_models=1
  local multi=0
  local n=0
  for t in $tools; do n=$((n + 1)); done
  [ "$n" -gt 1 ] && multi=1

  if [ "$multi" -eq 1 ] || [ "$NON_INTERACTIVE" -eq 1 ] || [ -n "$BASE_URL" ] || [ -n "$API_KEY" ]; then
    if [ "$DELEGATE" -eq 0 ]; then
      local want_models=1
      # 只有 pi / omo / opencode 需要模型列表
      local need_any=0
      for t in $tools; do
        case "$t" in pi|omo|opencode) need_any=1 ;; esac
      done
      [ "$need_any" -eq 0 ] && want_models=0
      collect_credentials "$want_models"
    fi
  fi

  for t in $tools; do
    local start_ts end_ts
    start_ts="$(date +%s)"
    rc=0
    run_tool "$t" ${PASSTHROUGH[@]+"${PASSTHROUGH[@]}"} || rc=$?
    end_ts="$(date +%s)"
    if [ "$rc" -eq 0 ]; then
      okc=$((okc + 1)); results+=("OK|$t|$((end_ts - start_ts))")
    else
      failc=$((failc + 1)); results+=("FAIL($rc)|$t|$((end_ts - start_ts))")
      if [ "$FAIL_FAST" -eq 1 ]; then
        warn "$(lc '--fail-fast: stopping' '--fail-fast：提前停止')"
        break
      fi
    fi
  done

  # ---- 汇总 ----
  printf '\n%s\n' "${BOLD}$(lc 'summary' '汇总')${RESET}" >&2
  printf '%s\n' "${DIM}────────────────────────────────────────────${RESET}" >&2
  local r status tool secs
  for r in ${results[@]+"${results[@]}"}; do
    status="${r%%|*}"; r="${r#*|}"; tool="${r%%|*}"; secs="${r##*|}"
    if [ "$status" = "OK" ]; then
      printf '  %s  %-12s %s\n' "${GREEN}✓${RESET}" "$(tool_title "$tool")" "${DIM}${secs}s${RESET}" >&2
    else
      printf '  %s  %-12s %s\n' "${RED}✗${RESET}" "$(tool_title "$tool")" "${DIM}${status} ${secs}s${RESET}" >&2
    fi
  done
  printf '%s\n' "${DIM}────────────────────────────────────────────${RESET}" >&2
  info "$(lc "$okc succeeded, $failc failed" "成功 $okc 个，失败 $failc 个")"
  [ "$failc" -eq 0 ]
}

cmd_list() {
  printf '\n%s\n\n' "${BOLD}$(lc 'supported tools' '支持的工具')"
  printf '  %-8s %-34s %-22s %s\n' "$(lc 'ID' 'ID')" "$(lc 'repository' '来源')" "$(lc 'upstream ref' '上游版本')" "$(lc 'cached' '缓存')"
  printf '  %s\n' "$(printf '%.0s─' $(seq 1 78) 2>/dev/null || printf -- '──────────────────────────────────────────────────────────────────────────────')"
  local t repo ref dir cached src
  for t in $ALL_TOOLS; do
    if tool_selfmanaged "$t"; then
      src="$(lc 'built-in (no upstream)' '内置实现（无上游）')"; ref="-"; dir=""
    else
      repo="$(tool_repo "$t")"; ref="$(ref_for "$t")"; dir="$(cache_dir_for "$t")"
      src="$REPO_OWNER/$repo"
    fi
    cached="${DIM}-${RESET}"
    if tool_selfmanaged "$t"; then
      cached="${DIM}n/a${RESET}"
    elif local_dir_for "$t" >/dev/null 2>&1; then
      cached="${GREEN}local${RESET}"
    elif [ -n "$dir" ] && [ -s "$dir/$(tool_entry "$t")" ]; then
      cached="${GREEN}yes${RESET}"
    fi
    printf '  %-8s %-34s %-22s %b\n' "$t" "$src" "${ref:0:20}" "$cached"
  done
  printf '\n'
  info "$(lc "cache: $CACHE_BASE" "缓存目录：$CACHE_BASE")"
  printf '\n'
}

cmd_doctor() {
  printf '\n%s\n\n' "${BOLD}$(lc 'environment check' '环境检查')"
  printf '  %-18s %s\n' "$(lc 'platform' '平台')" "$OS / $ARCH"
  printf '  %-18s %s\n' "$(lc 'shell' 'Shell')" "${BASH_VERSION} (${BASH})"
  printf '  %-18s %s\n' "$(lc 'user' '用户')" "$(id -un) (uid=$(id -u))"
  printf '  %-18s %s\n' "$(lc 'home' '家目录')" "$HOME"
  printf '  %-18s %s\n' "$(lc 'language' '语言')" "$LANG_CODE"
  printf '  %-18s %s\n' "$(lc 'cache' '缓存目录')" "$CACHE_BASE"
  printf '\n'

  printf '%s\n' "${BOLD}$(lc 'commands' '命令')${RESET}"
  local c
  for c in curl wget git node npm python3 jq sudo; do
    if command -v "$c" >/dev/null 2>&1; then
      printf '  %s  %-8s %s\n' "${GREEN}✓${RESET}" "$c" "$(command -v "$c")"
    else
      printf '  %s  %-8s %s\n' "${YELLOW}·${RESET}" "$c" "${DIM}$(lc 'not found' '未安装')${RESET}"
    fi
  done
  printf '\n'

  printf '%s\n' "${BOLD}$(lc 'installed CLIs' '已安装的 CLI')${RESET}"
  local bin
  for bin in pi omo claude codex grok opencode; do
    if command -v "$bin" >/dev/null 2>&1; then
      printf '  %s  %-8s %s\n' "${GREEN}✓${RESET}" "$bin" "$(command -v "$bin")"
    else
      printf '  %s  %-8s %s\n' "${YELLOW}·${RESET}" "$bin" "${DIM}$(lc 'not found' '未安装')${RESET}"
    fi
  done
  printf '\n'

  printf '%s\n' "${BOLD}$(lc 'config files' '配置文件')${RESET}"
  local f
  for f in "$OPENCODE_CONFIG" "$HOME/.grok/config.toml" "$HOME/.codex/config.toml" "$HOME/.codex/auth.json"; do
    if [ -f "$f" ]; then
      printf '  %s  %s  %s\n' "${GREEN}✓${RESET}" "$f" "${DIM}$(ls -l "$f" | awk '{print $1}')${RESET}"
    else
      printf '  %s  %s\n' "${YELLOW}·${RESET}" "$f"
    fi
  done
  printf '\n'
}

cmd_download() {
  local tools
  tools="$(resolve_selection "$COMMAND_TOOLS")"
  local t rc=0
  for t in $tools; do
    step "$(lc "prefetch $(tool_title "$t")" "预取 $(tool_title "$t")")"
    if tool_selfmanaged "$t"; then
      info "$(lc 'built-in: nothing to download' '内置实现：无需下载')"
      continue
    fi
    ensure_tool "$t" >/dev/null || { err "$(lc "$t failed" "$t 失败")"; rc=1; }
  done
  [ "$rc" -eq 0 ] && ok "$(lc 'cache is ready' '缓存已就绪')"
  return $rc
}

cmd_interactive_pick() {
  printf '\n%s\n\n' "${BOLD}$(lc 'Which tools do you want to set up?' '要配置哪些工具？')"
  local t i=1
  for t in $ALL_TOOLS; do
    printf '  %s) %-12s %s\n' "$i" "$(tool_title "$t")" "${DIM}$(tool_homepage "$t")${RESET}"
    i=$((i + 1))
  done
  printf '  %s) %s\n\n' "$i" "$(lc 'all of the above' '以上全部')"
  local ans=""
  ask ans "$(lc 'choose (e.g. 1,3 or 7 for all)' '请选择（如 1,3；输入 7 表示全部）')" "$i"
  case "$ans" in
    "$i"|"all"|"a") COMMAND_TOOLS=""; return 0 ;;
  esac
  local picked="" n
  local IFS=','
  for n in $ans; do
    n="$(printf '%s' "$n" | tr -d '[:space:]')"
    case "$n" in
      1) picked="$picked pi" ;;
      2) picked="$picked omo" ;;
      3) picked="$picked claude" ;;
      4) picked="$picked codex" ;;
      5) picked="$picked grok" ;;
      6) picked="$picked opencode" ;;
    esac
  done
  unset IFS
  [ -n "$picked" ] || die "$(lc 'nothing selected' '未选择任何工具')"
  COMMAND_TOOLS="$picked"
}

# ---------------------------------------------------------------------------
# 13. 参数解析
# ---------------------------------------------------------------------------
usage() {
  cat <<EOF
${BOLD}$AICLI_NAME $AICLI_VERSION${RESET} — $(lc 'one entry point for the zxfccmm4 AI CLI installers' 'zxfccmm4 系列 AI CLI 安装脚本的统一入口')

${BOLD}$(lc 'USAGE' '用法')${RESET}
  $AICLI_NAME [options] [command] [tool...]
  $AICLI_NAME all [tools...]
  $AICLI_NAME pi|omo|claude|codex|grok|opencode
  $AICLI_NAME list | doctor | download [tools] | help

${BOLD}$(lc 'TOOLS' '工具')${RESET}
  pi       $(lc 'install + configure Pi (pi.dev)' '安装并配置 Pi（pi.dev）')
  omo      $(lc 'install + configure OmO (omo.dev)' '安装并配置 OmO（omo.dev）')
  claude   $(lc 'install + configure Claude Code' '安装并配置 Claude Code')
  codex    $(lc 'install + configure Codex CLI' '安装并配置 Codex CLI')
  grok     $(lc 'install Grok Build + write ~/.grok/config.toml' '安装 Grok Build 并写入 ~/.grok/config.toml')
  opencode $(lc 'install + configure OpenCode (opencode.ai)' '安装并配置 OpenCode（opencode.ai）')

${BOLD}$(lc 'OPTIONS' '选项')${RESET}
  -y, --yes                  $(lc 'non-interactive' '非交互模式')
  -i, --interactive          $(lc 'force upstream wizards' '强制使用上游向导')
      --delegate             $(lc 'never collect credentials; let each upstream wizard ask' '不收集凭据，完全交给上游向导')
  -l, --lang en|zh           $(lc 'output/wizard language' '输出与向导语言')
      --base-url URL         $(lc 'API endpoint base URL' '接口 base URL')
      --api-key KEY          $(lc 'API key / token' 'API key / token')
      --models a,b,c         $(lc 'model ids to register (pi/omo/opencode)' '要注册的模型 id（pi/omo/opencode）')
      --model ID             $(lc 'default model (claude/codex/grok/opencode)' '默认模型（claude/codex/grok/opencode）')
      --grok-alias NAME      $(lc 'GrokBuild local model alias' 'GrokBuild 本地模型别名')
      --grok-search on|off   $(lc 'enable server-side Search Tool' '开启服务端 Search Tool')
      --opencode-provider ID $(lc 'OpenCode provider id (default: derived from host)' 'OpenCode provider id（默认由 host 推导）')
      --opencode-method M    $(lc 'opencode install method: official|npm' 'OpenCode 安装方式：official|npm')
      --opencode-config FILE $(lc 'path to opencode.json' 'opencode.json 路径')
      --only a,b             $(lc 'only these tools' '只处理这些工具')
      --skip a,b             $(lc 'skip these tools' '跳过这些工具')
      --skip-install         $(lc 'configure only, do not install/update the CLI' '只配置，不安装/更新 CLI')
      --ref REF              $(lc 'upstream git ref (default: main)' '上游 git ref（默认 main）')
      --pin                  $(lc 'use verified pinned upstream commits' '使用已验证的固定提交')
      --refresh              $(lc 'ignore cache and re-download' '忽略缓存重新下载')
      --no-cache             $(lc 'do not use/write the download cache' '不使用/不写入下载缓存')
      --fail-fast            $(lc 'stop at the first failure' '遇到第一个失败即停止')
      --dry-run              $(lc 'print what would happen' '只显示将要执行的操作')
  -h, --help                 $(lc 'this help' '显示帮助')
  -V, --version              $(lc 'version' '显示版本')
      --                     $(lc 'everything after is forwarded to the upstream script' '之后的参数原样透传给上游脚本')

${BOLD}$(lc 'EXAMPLES' '示例')${RESET}
  # $(lc 'everything, credentials asked once' '全部安装，凭据只问一次')
  $AICLI_NAME all

  # $(lc 'non-interactive Claude Code with a custom gateway' '非交互安装 Claude Code（自定义网关）')
  $AICLI_NAME claude -y --base-url https://gw.example.com --api-key sk-xxx

  # $(lc 'Pi only, explicit models' '只装 Pi，显式指定模型')
  $AICLI_NAME pi -y --base-url https://gw.example.com/v1 --api-key sk-xxx --models gpt-5,gpt-5-mini

  # $(lc 'Grok Build with search enabled' 'Grok Build 并开启搜索')
  $AICLI_NAME grok -y --base-url https://gw.example.com/v1 --api-key sk-xxx --grok-search on

  # $(lc 'forward flags to the upstream script' '把参数透传给上游脚本')
  $AICLI_NAME codex -- --restore

  # $(lc 'OpenCode with a custom OpenAI-compatible gateway' 'OpenCode 接自定义 OpenAI 兼容网关')
  $AICLI_NAME opencode -y --base-url https://gw.example.com/v1 --api-key sk-xxx --models gpt-5,gpt-5-mini

  # $(lc 'reproducible install at verified commits' '在已验证提交上安装（可复现）')
  $AICLI_NAME all --pin

${BOLD}$(lc 'ENVIRONMENT' '环境变量')${RESET}
  AICLI_BASE_URL AICLI_API_KEY AICLI_MODELS AICLI_MODEL AICLI_LANG
  AICLI_REF AICLI_CACHE_DIR AICLI_RAW_HOST AICLI_OWNER
  AICLI_OPENCODE_CONFIG AICLI_OPENCODE_PROVIDER AICLI_OPENCODE_METHOD

${BOLD}$(lc 'UPSTREAM' '上游仓库')${RESET}
  $(lc 'this script wraps, and does not modify, these MIT-licensed repositories:' '本脚本仅封装、不修改以下 MIT 许可仓库：')
$(for t in $ALL_TOOLS; do if tool_selfmanaged "$t"; then printf '  %-8s %s\n' "$t" "$(lc 'built-in (no upstream repo)' '内置实现（无上游仓库）')"; else printf '  %-8s https://github.com/%s/%s\n' "$t" "$REPO_OWNER" "$(tool_repo "$t")"; fi; done)
EOF
}

parse_args() {
  while [ $# -gt 0 ]; do
    case "$1" in
      -y|--yes) NON_INTERACTIVE=1; shift ;;
      -i|--interactive) FORCE_INTERACTIVE=1; shift ;;
      --delegate) DELEGATE=1; shift ;;
      -l|--lang) [ $# -ge 2 ] || die "--lang $(lc 'needs a value' '需要一个值')"; LANG_CODE="$(normalize_lang "$2")"; shift 2 ;;
      --base-url) [ $# -ge 2 ] || die "--base-url $(lc 'needs a value' '需要一个值')"; BASE_URL="$2"; shift 2 ;;
      --api-key|--token) [ $# -ge 2 ] || die "--api-key $(lc 'needs a value' '需要一个值')"; API_KEY="$2"; shift 2 ;;
      --models) [ $# -ge 2 ] || die "--models $(lc 'needs a value' '需要一个值')"; MODELS="$2"; shift 2 ;;
      --model) [ $# -ge 2 ] || die "--model $(lc 'needs a value' '需要一个值')"; MODEL="$2"; shift 2 ;;
      --grok-alias) [ $# -ge 2 ] || die "--grok-alias $(lc 'needs a value' '需要一个值')"; GROK_ALIAS="$2"; shift 2 ;;
      --grok-search) [ $# -ge 2 ] || die "--grok-search $(lc 'needs a value' '需要一个值')"; GROK_SEARCH="$2"; shift 2 ;;
      --opencode-provider) [ $# -ge 2 ] || die "--opencode-provider $(lc 'needs a value' '需要一个值')"; OPENCODE_PROVIDER="$2"; shift 2 ;;
      --opencode-provider-name) [ $# -ge 2 ] || die "--opencode-provider-name $(lc 'needs a value' '需要一个值')"; OPENCODE_PROVIDER_NAME="$2"; shift 2 ;;
      --opencode-npm) [ $# -ge 2 ] || die "--opencode-npm $(lc 'needs a value' '需要一个值')"; OPENCODE_NPM="$2"; shift 2 ;;
      --opencode-method) [ $# -ge 2 ] || die "--opencode-method $(lc 'needs a value' '需要一个值')"; OPENCODE_METHOD="$2"; shift 2 ;;
      --opencode-config) [ $# -ge 2 ] || die "--opencode-config $(lc 'needs a value' '需要一个值')"; OPENCODE_CONFIG="$2"; shift 2 ;;
      --only) [ $# -ge 2 ] || die "--only $(lc 'needs a value' '需要一个值')"; ONLY="$2"; shift 2 ;;
      --skip) [ $# -ge 2 ] || die "--skip $(lc 'needs a value' '需要一个值')"; SKIP="$2"; shift 2 ;;
      --skip-install) SKIP_INSTALL=1; shift ;;
      --ref) [ $# -ge 2 ] || die "--ref $(lc 'needs a value' '需要一个值')"; UPSTREAM_REF="$2"; USE_PINNED=0; shift 2 ;;
      --pin) USE_PINNED=1; shift ;;
      --refresh) REFRESH=1; shift ;;
      --no-cache) USE_CACHE=0; shift ;;
      --fail-fast) FAIL_FAST=1; shift ;;
      --dry-run) DRY_RUN=1; shift ;;
      -h|--help) usage; exit 0 ;;
      -V|--version) printf '%s %s\n' "$AICLI_NAME" "$AICLI_VERSION"; exit 0 ;;
      --) shift; PASSTHROUGH=("$@"); break ;;
      -*) die "$(lc "unknown option: $1" "未知选项：$1")" ;;
      *)
        case "$1" in
          all|list|doctor|download|help)
            if [ -z "$COMMAND" ]; then COMMAND="$1"; shift
            else die "$(lc "unexpected argument: $1" "多余参数：$1")"; fi
            ;;
          pi|omo|claude|codex|grok|opencode)
            if [ -z "$COMMAND" ]; then COMMAND="$1"; shift
            else SELECTED+=("$1"); shift; fi
            ;;
          *)
            # 支持逗号分隔（如 `ai-cli-setup opencode,grok`）
            local parts part ok=1
            parts="$(printf '%s' "$1" | tr ',' ' ')"
            for part in $parts; do
              tool_valid "$part" || { ok=0; break; }
            done
            if [ "$ok" -eq 1 ]; then
              for part in $parts; do SELECTED+=("$part"); done
              shift
            else
              die "$(lc "unknown command or tool: $1" "未知命令或工具：$1")"
            fi
            ;;
        esac
        ;;
    esac
  done

  # 位置参数里的工具 -> 追加到选择
  if [ ${#SELECTED[@]} -gt 0 ]; then
    local s=""
    local t
    for t in ${SELECTED[@]+"${SELECTED[@]}"}; do s="$s,$t"; done
    s="${s#,}"
    if [ -n "$ONLY" ]; then ONLY="$ONLY,$s"; else ONLY="$s"; fi
  fi
}

# ---------------------------------------------------------------------------
# 14. main
# ---------------------------------------------------------------------------
COMMAND_TOOLS=""

main() {
  parse_args "$@"

  case "$COMMAND" in
    help) usage; exit 0 ;;
    list) cmd_list; exit 0 ;;
    doctor) cmd_doctor; exit 0 ;;
    download) cmd_download; exit $? ;;
  esac

  if [ -z "$COMMAND" ]; then
    if [ "$NON_INTERACTIVE" -eq 1 ] || ! have_tty; then
      COMMAND="all"
    else
      printf '\n%s\n' "${BOLD}$AICLI_NAME $AICLI_VERSION${RESET} — $(lc 'unified AI CLI setup' '统一 AI CLI 安装入口')"
      cmd_interactive_pick
      COMMAND="all"
    fi
  fi

  case "$COMMAND" in
    all) COMMAND_TOOLS="$ONLY" ;;
    pi|omo|claude|codex|grok|opencode)
      if [ -n "$ONLY" ]; then COMMAND_TOOLS="$ONLY"; else COMMAND_TOOLS="$COMMAND"; fi
      ;;
  esac

  if [ "$NON_INTERACTIVE" -eq 1 ] && [ "$DRY_RUN" -eq 0 ]; then
    info "$(lc 'non-interactive mode' '非交互模式')"
  fi

  cmd_run
  exit $?
}

main "$@"
