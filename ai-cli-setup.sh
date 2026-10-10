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

VERSION="2.0.0"
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
case "$(printf '%s' "${AICLI_ASSUME_TTY:-0}" | tr '[:upper:]' '[:lower:]')" in
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
read_line() {
  local __var="$1" __prompt="$2" __secret="${3:-0}"
  if [ "$__secret" = "1" ]; then read_secret "$__var" "$__prompt"; return; fi
  local __ans=""
  if stdin_is_input; then
    printf '%s' "$__prompt" >&2
    IFS= read -r __ans || true
  elif { exec 9<>/dev/tty; } 2>/dev/null; then
    printf '%s' "$__prompt" > /dev/tty
    IFS= read -r __ans < /dev/tty || true
    exec 9>&- 9<&-
  else
    printf '%s' "$__prompt" >&2
    IFS= read -r __ans || true
  fi
  printf -v "$__var" '%s' "$__ans"
}

secret_mask() {
  local s="${1:-}"
  if [ -z "$s" ] || [ ${#s} -le 6 ]; then
    printf '%s' "$(printf '%.*s' ${#s} '********')"
  else
    printf '%s%s%s' "${s:0:3}" "$(printf '%.*s' $((${#s} - 6)) '********************************************************')" "${s: -3}"
  fi
}

read_secret() {
  local __var="$1" __prompt="$2" __c="" __buf="" __prev=0 __m=""
  local __in="/dev/tty" __out="/dev/tty"
  stdin_is_input && { __in="/dev/stdin"; __out="/dev/stderr"; }
  printf '%s' "$__prompt" > "$__out" 2>/dev/null || printf '%s' "$__prompt" >&2

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
          printf '\b%.0s' $(seq 1 $__prev) > "$__out" 2>/dev/null || true
          printf '%s' "$__m" > "$__out" 2>/dev/null || true
          local __pad=$((__prev - ${#__m}))
          [ $__pad -gt 0 ] && printf '%*s' $__pad '' > "$__out" 2>/dev/null
          __prev=${#__m}
        fi ;;
      $'\x15')
        if [ "$__prev" -gt 0 ]; then
          printf '\b%.0s' $(seq 1 $__prev) > "$__out" 2>/dev/null || true
          printf '%*s' "$__prev" '' > "$__out" 2>/dev/null || true
          printf '\b%.0s' $(seq 1 $__prev) > "$__out" 2>/dev/null || true
        fi
        __buf=""; __prev=0 ;;
      $'\x04') break ;;
      *)
        __buf="${__buf}${__c}"; __m="$(secret_mask "$__buf")"
        printf '\b%.0s' $(seq 1 $__prev) > "$__out" 2>/dev/null || true
        printf '%s' "$__m" > "$__out" 2>/dev/null || true
        __prev=${#__m} ;;
    esac
  done
  [ -n "$__saved" ] && { stty "$__saved" < "$__in" 2>/dev/null || true; trap - INT TERM HUP; }
  printf '\n' > "$__out" 2>/dev/null || true
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
  Darwin) OS=macos ;; Linux) OS=linux ;; *) OS="$(uname -s | tr '[:upper:]' '[:lower:]')" ;;
esac
case "$(uname -m)" in
  x86_64|amd64) ARCH=x86_64 ;; arm64|aarch64) ARCH=arm64 ;; *) ARCH="$(uname -m)" ;;
esac
is_root() { [ "$(id -u)" -eq 0 ]; }

have() { command -v "$1" >/dev/null 2>&1; }

# ============================================================
# 6. agent 清单
# ============================================================
ALL_AGENTS="pi omo claude codex grok opencode"

agent_valid() { case "$1" in pi|omo|claude|codex|grok|opencode) return 0 ;; *) return 1 ;; esac; }
agent_title() {
  case "$1" in
    pi) printf 'Pi' ;; omo) printf 'OmO' ;; claude) printf 'Claude Code' ;;
    codex) printf 'Codex CLI' ;; grok) printf 'Grok Build' ;; opencode) printf 'OpenCode' ;;
  esac
}
agent_homepage() {
  case "$1" in
    pi) printf 'https://pi.dev' ;; omo) printf 'https://omo.dev' ;;
    claude) printf 'https://claude.com/product/claude-code' ;;
    codex) printf 'https://github.com/openai/codex' ;;
    grok) printf 'https://x.ai/cli' ;; opencode) printf 'https://opencode.ai' ;;
  esac
}
# 安装命令（官方渠道）
agent_bin() {
  case "$1" in
    pi) printf 'pi' ;; omo) printf 'omo' ;; claude) printf 'claude' ;;
    codex) printf 'codex' ;; grok) printf 'grok' ;; opencode) printf 'opencode' ;;
  esac
}
# 该 agent 是否只在 Linux 安装
agent_linux_only() { case "$1" in claude) return 0 ;; *) return 1 ;; esac; }
# 配置是否需要模型列表（多模型注册）
agent_needs_models() { case "$1" in pi|omo|opencode) return 0 ;; *) return 1 ;; esac; }
# 配置是否需要单个默认模型
agent_needs_model() { case "$1" in claude|codex|grok|opencode) return 0 ;; *) return 1 ;; esac; }

# ============================================================
# 7. 安装（全自研：官方 installer / npm，不依赖 zxfccmm4 仓库）
# ============================================================
need_dl() { have curl || have wget || die "$(lc 'need curl or wget' '需要 curl 或 wget')"; }

run_official() {  # run_official <url> [args...]
  local url="$1"; shift
  need_dl
  if have curl; then curl -fsSL "$url" | bash -s -- "$@"; else wget -qO- "$url" | bash -s -- "$@"; fi
}

ensure_node() {
  have node && return 0
  warn "$(lc 'node not found; installing Node.js via nodesource (needs root)' '未找到 node；通过 nodesource 安装 Node.js（需要 root）')"
  if [ "$OS" = "macos" ]; then
    have brew || die "$(lc 'install Homebrew first (https://brew.sh)' '请先安装 Homebrew（https://brew.sh）')"
    brew install node
  else
    curl -fsSL https://deb.nodesource.com/setup_22.x | bash - >/dev/null 2>&1 || true
    ${SUDO_CMD:-} apt-get install -y nodejs >/dev/null 2>&1 || die "failed to install nodejs"
  fi
  have node || die "$(lc 'node install failed' 'node 安装失败')"
}

ensure_npm() { ensure_node; have npm || die "$(lc 'npm not found' '未找到 npm')"; }

install_pi() {
  if have pi; then info "$(lc 'pi already installed, updating' 'pi 已安装，检查更新')"; pi update >/dev/null 2>&1 || true; return 0; fi
  # npm 优先：完全非交互。官方 install.sh 末尾会问 "Start pi now?" 且默认 Y，
  # 管道模式下会把 pi 启动进安装流程卡住。
  ensure_npm && npm install -g --ignore-scripts @earendil-works/pi-coding-agent && return 0
  have curl && curl -fsSL https://pi.dev/install.sh | sh
}
install_omo() {
  export OMO_INSTALL_ALLOW_SUDO=1   # 服务器常以 root 运行
  if have omo; then info "$(lc 'omo already installed, updating' 'omo 已安装，检查更新')"; omo update >/dev/null 2>&1 || true; return 0; fi
  if have curl; then curl -fsSL https://get.omo.dev/install.sh | bash
  elif have wget; then wget -qO- https://get.omo.dev/install.sh | bash
  else ensure_npm && npm install -g omo-ai; fi
}
install_claude() {
  if have claude; then info "$(lc 'claude already installed' 'claude 已安装')"; return 0; fi
  if have curl; then curl -fsSL https://claude.ai/install.sh | bash
  elif have wget; then wget -qO- https://claude.ai/install.sh | bash
  else ensure_npm && npm install -g @anthropic-ai/claude-code; fi
}
install_codex() {
  if have codex; then info "$(lc 'codex already installed' 'codex 已安装')"; return 0; fi
  ensure_npm && npm install -g @openai/codex
}
install_grok() {
  export PATH="$HOME/.grok/bin:$PATH"
  if have grok; then info "$(lc 'grok already installed' 'grok 已安装')"; return 0; fi
  run_official https://x.ai/cli/install.sh
  export PATH="$HOME/.grok/bin:$PATH"
  have grok || die "$(lc 'grok install failed' 'grok 安装失败')"
}
install_opencode() {
  if have opencode; then info "$(lc 'opencode already installed' 'opencode 已安装')"; return 0; fi
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
  ensure_npm && npm install -g opencode-ai
}

# 安装后清 bash 命令路径缓存并确认二进制真实可用：
# npm 重装会把 bin 换位置，bash 缓存的旧路径（如 /usr/local/bin/codex）导致
# "No such file or directory"，hash -r 后用真实路径再探测。
post_install_check() {
  local a="$1" bin path
  bin="$(agent_bin "$a")"
  hash -r 2>/dev/null || true
  if path="$(command -v "$bin" 2>/dev/null)" && [ -x "$path" ]; then
    ok "$(agent_title "$a") -> $path"
  else
    # 二进制可能在本次安装新增的 PATH 目录里（如 ~/.local/bin），当前 shell 尚未包含
    local cand
    for cand in "$HOME/.local/bin/$bin" "$HOME/.grok/bin/$bin" "$HOME/.bun/bin/$bin" "$HOME/.opencode/bin/$bin"; do
      if [ -x "$cand" ]; then ok "$(agent_title "$a") -> $cand"; return 0; fi
    done
    warn "$(lc "$bin not on PATH yet; open a new shell or re-login" "$bin 尚不在 PATH；请新开终端或重新登录")"
  fi
}

install_agent() {
  local a="$1"
  step "$(lc "install $(agent_title "$a")" "安装 $(agent_title "$a")")"
  if [ "$SKIP_INSTALL" -eq 1 ]; then info "$(lc 'skip-install: not touching the binary' '--skip-install：跳过安装')"; return 0; fi
  if [ "$DRY_RUN" -eq 1 ]; then info "$(lc 'dry-run: would install' 'dry-run：将安装') $(agent_title "$a")"; return 0; fi
  case "$a" in
    pi) install_pi ;;
    omo) install_omo ;;
    claude) install_claude ;;
    codex) install_codex ;;
    grok) install_grok ;;
    opencode) install_opencode ;;
  esac
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
  cp -p "$f" "$bak" && info "$(lc "backed up: $f -> $bak" "已备份：$f -> $bak")"
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
  local s="${1:-}"
  if have node; then node -e 'console.log(JSON.stringify(process.argv[1]))' "$s"
  elif have python3; then python3 -c 'import json,sys; print(json.dumps(sys.argv[1]))' "$s"
  else printf '"%s"' "${s//\"/\\\"}"; fi
}

# --- pi / omo：结构相同（models.json + settings.json） ---
# agent_dir: ~/.pi/agent 或 ~/.omo/agent
write_pi_like() {
  local agent_dir="$2" provider="$3"
  local mfile="$agent_dir/models.json" sfile="$agent_dir/settings.json"
  mkdir -p "$agent_dir"
  backup_file "$mfile"; backup_file "$sfile"

  local mjson sjson tmpm
  mjson="$(build_pi_models_json "$provider")"
  [ -n "$mjson" ] || { err "$(lc 'failed to build models.json (need node/python3)' '生成 models.json 失败（需要 node/python3）')"; return 1; }
  sjson="$(build_pi_settings_json || true)"

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
  local provider="$1"
  PI_PROVIDER="$provider" PI_BASE_URL="$BASE_URL" PI_API_KEY="$API_KEY" PI_MODELS="$MODELS" \
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
  ' 2>/dev/null || \
  PI_PROVIDER="$provider" PI_BASE_URL="$BASE_URL" PI_API_KEY="$API_KEY" PI_MODELS="$MODELS" \
  python3 -c '
import json,os
env=os.environ
models=[m.strip() for m in env.get("PI_MODELS","").split(",") if m.strip()]
out={"providers":{env["PI_PROVIDER"]:{"baseUrl":env["PI_BASE_URL"],"api":"openai-completions","apiKey":env["PI_API_KEY"],"models":[{"id":m,"name":m} for m in models]}}}
print(json.dumps(out,indent=2))
'
}

# defaultModel 为纯模型 id（不带 provider 前缀）
build_pi_settings_json() {
  local first=""
  [ -n "$MODELS" ] && first="$(printf '%s' "$MODELS" | cut -d, -f1 | tr -d '[:space:]')"
  [ -z "$first" ] && first="$MODEL"
  [ -z "$first" ] && return 1
  printf '{\n  "defaultProvider": "%s",\n  "defaultModel": "%s"\n}\n' \
    "$(printf '%s' "$first" | sed 's/"/\\"/g')" "$(printf '%s' "$first" | sed 's/"/\\"/g')"
}

provider_from_host() {
  local u="${1:-$BASE_URL}"
  printf '%s' "$u" | sed -E 's#^https?://##; s#/.*$##; s#[^A-Za-z0-9]+#-#g' | sed 's/^-//; s/-$//'
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
  mkdir -p "$dir"
  backup_file "$f"
  tmp="$(mktemp "${TMPDIR:-/tmp}/aicli-c.XXXXXX")"
  if ! CLAUDE_FILE="$f" CLAUDE_OUT="$tmp" CLAUDE_BASE="$base_clean" CLAUDE_KEY="$API_KEY" CLAUDE_MODEL="$model" \
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
  ' 2>/dev/null; then
    err "$(lc 'failed to build claude settings.json (need node)' '生成 claude settings.json 失败（需要 node）')"
    rm -f "$tmp"; return 1
  fi
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
  mkdir -p "$dir"
  backup_file "$cf"; backup_file "$af"
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
  mkdir -p "$HOME/.grok"
  backup_file "$f"
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
  mkdir -p "$(dirname "$f")"
  backup_file "$f"
  local provider provider_name npm_pkg
  case "$(printf '%s' "$BASE_URL" | tr '[:upper:]' '[:lower:]')" in
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
  # V2 检测：用户显式 AICLI_OPENCODE_V2=1，或已装二进制 >= 2.0，或配置里已有 providers 键
  local ocv=1
  local prov_upper; prov_upper="$(printf '%s' "$provider" | tr '[:lower:]-' '[:upper:]_')"
  if [ -n "${AICLI_OPENCODE_V2:-}" ]; then
    case "$AICLI_OPENCODE_V2" in 1|true|yes) ocv=2 ;; *) ocv=1 ;; esac
  elif have opencode; then
    ocv="$(opencode --version 2>/dev/null | grep -qE '^2\.' && printf 2 || printf 1)"
  elif grep -q '"providers"' "$f" 2>/dev/null; then
    ocv=2
  fi

  local tmp; tmp="$(mktemp "${TMPDIR:-/tmp}/aicli-o.XXXXXX")"
  if [ "$ocv" = "2" ]; then
    # ---- OpenCode V2：providers/settings/package + {env:} 凭据引用 ----
    # key 不落盘：写入 {env:VAR} 引用，并把真实 key 放进该 env 变量。
    # shellcheck disable=SC2155
    local env_var="AICLI_${prov_upper}_API_KEY"
    have node || true
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
    if [ "$DRY_RUN" -eq 0 ]; then
      # 把真实 key 写入 shell 配置（export AICLI_XXX_API_KEY），配置文件只留引用
      local shellrc=""
      for cand in "$HOME/.bashrc" "$HOME/.zshrc"; do
        [ -f "$cand" ] && shellrc="$cand" && break
      done
      [ -n "$shellrc" ] || shellrc="$HOME/.bashrc"
      if ! grep -q "^export ${env_var}=" "$shellrc" 2>/dev/null; then
        printf '\n# %s gateway key (added by ai-cli-setup)\nexport %s=%s\n' "$provider" "$env_var" "'$API_KEY'" >> "$shellrc"
        info "$(lc "exported $env_var in $shellrc (key not stored in opencode.json)" "已在 $shellrc 导出 $env_var（key 不写入 opencode.json）")"
      else
        # 更新已有值
        python3 - "$shellrc" "$env_var" "$API_KEY" <<'PYK' 2>/dev/null || true
import sys, re
path, var, val = sys.argv[1], sys.argv[2], sys.argv[3]
s = open(path).read()
s = re.sub(r"^export %s=.*$" % var, "export %s='%s'" % (var, val), s, flags=re.M)
open(path, "w").write(s)
PYK
        info "$(lc "updated $env_var in $shellrc" "已更新 $shellrc 中的 $env_var")"
      fi
    fi
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
          "$(printf '%s' "$BASE_URL" | sed 's/"/\\"/g')" "$(printf '%s' "$provider" | tr '[:lower:]-' '[:upper:]_')"
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
  ok "$(lc "wrote $f" "已写入 $f") [v$ocv]"
  info "$(lc 'provider' 'provider')  $provider  $(lc 'default model' '默认模型')  ${model:-(none)}"
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
  [ -n "$(printf '%s' "$spec" | tr -d '[:space:]')" ] || return 1
  max="$(agent_count)"
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
  local ans=""
  printf '\n%s\n\n' "${BOLD}Select language  /  选择语言${RESET}" >&2
  printf '  1) English\n  2) 中文 (Chinese)\n\n' >&2
  read_line ans "choose / 请选择 " 
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
    printf '  %s) %-12s %s\n' "$i" "$(agent_title "$a")" "${DIM}$(agent_homepage "$a")${RESET}" >&2
    i=$((i+1))
  done
  printf '  %s) %s\n\n' "$all_key" "$(lc 'all of the above' '以上全部')" >&2
  printf '%s\n\n' "${DIM}$(lc "  one number = single   |   1,3 or 1-3 = several   |   a or $all_key = all" "  单个数字 = 单选   |   1,3 或 1-3 = 多选   |   a 或 $all_key = 全部")${RESET}" >&2
  for _ in 1 2 3; do
    read_line ans "$(lc 'select' '请选择') "
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

# ============================================================
# 12. 凭据收集（安装完成后、配置前）
# ============================================================
collect_credentials() {
  local need_models=0 need_model=0 a
  for a in $(printf '%s' "$SELECTED" | tr ',' ' '); do
    agent_needs_models "$a" && need_models=1
    agent_needs_model "$a" && need_model=1
  done

  if [ -z "$BASE_URL" ]; then
    [ "$NON_INTERACTIVE" -eq 1 ] && die "$(lc 'missing --base-url' '缺少 --base-url')"
    read_line BASE_URL "$(lc 'API endpoint base URL (e.g. https://api.example.com/v1)' '接口 base URL（例：https://api.example.com/v1）') "
    [ -n "$BASE_URL" ] || die "$(lc 'base URL is required' 'base URL 必填')"
  fi
  if [ -z "$API_KEY" ]; then
    [ "$NON_INTERACTIVE" -eq 1 ] && die "$(lc 'missing --api-key' '缺少 --api-key')"
    read_line API_KEY "$(lc 'API key' 'API key') " 1
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
        while [ -z "$MODELS" ]; do
          read_line MODELS "$(lc 'model ids (comma separated, required)' '模型 id（逗号分隔，必填）') "
          [ -z "$MODELS" ] && warn "$(lc 'at least one model is required' '至少需要一个模型')"
        done
      fi
    fi
  fi
  # 单默认模型（claude/codex/grok/opencode）：拉到列表时默认第一个
  if [ "$need_model" -eq 1 ] && [ -z "$MODEL" ]; then
    if [ -n "$MODELS" ]; then MODEL="$(printf '%s' "$MODELS" | cut -d, -f1 | tr -d '[:space:]')"
    elif [ "$NON_INTERACTIVE" -eq 0 ]; then
      read_line MODEL "$(lc 'default model id (for claude/codex/grok/opencode)' '默认模型 id（claude/codex/grok/opencode 用）') "
    fi
  fi
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
  claude      Claude Code       claude.com                claude.ai/install.sh（仅 Linux/WSL）
  codex       Codex CLI         openai/codex              npm/@openai/codex
  grok        Grok Build        x.ai/cli                  x.ai/cli/install.sh
  opencode    OpenCode          opencode.ai               opencode.ai/install

${BOLD}$(lc 'OPTIONS' '选项')${RESET}
  -y, --yes              $(lc 'non-interactive' '非交互模式')
      --base-url URL     $(lc 'API endpoint base URL' '接口 base URL')
      --api-key KEY      $(lc 'API key (masked input: first3+***+last3)' 'API key（掩码输入：前3+***+后3）')
      --models a,b,c     $(lc 'model ids to register (pi/omo/opencode)' '注册的模型 id（pi/omo/opencode）')
      --model ID         $(lc 'default model (claude/codex/grok/opencode)' '默认模型（claude/codex/grok/opencode）')
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

${BOLD}$(lc 'CONFIG FILES' '配置文件')${RESET}
  pi       ~/.pi/agent/{models,settings}.json
  omo      ~/.omo/agent/{models,settings}.json
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
      --base-url) BASE_URL="$2"; shift 2 ;;
      --api-key) API_KEY="$2"; shift 2 ;;
      --models) MODELS="$2"; shift 2 ;;
      --model) MODEL="$2"; shift 2 ;;
      --grok-alias) GROK_ALIAS="$2"; shift 2 ;;
      -h|--help) usage; exit 0 ;;
      -V|--version) printf '%s %s\n' "$NAME" "$VERSION"; exit 0 ;;
      list|doctor|help) COMMAND="$1"; shift ;;
      all) SELECTED="$(printf '%s' "$ALL_AGENTS" | tr ' ' ',')"; shift ;;
      pi|omo|claude|codex|grok|opencode)
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
  esac

  printf '\n%s\n' "${BOLD}$NAME $VERSION${RESET} — $(lc 'AI agent installer + configurator' 'AI agent 安装 + 配置')${RESET}" >&2

  if interactive_run; then prompt_language; fi

  # 选 agent
  if [ -z "$SELECTED" ]; then
    if interactive_run; then prompt_agents
    else SELECTED="$(printf '%s' "$ALL_AGENTS" | tr ' ' ',')"; fi
  fi

  # --- 阶段 1：安装 ---
  local a rc=0 okc=0 failc=0
  local -a results=()
  for a in $(printf '%s' "$SELECTED" | tr ',' ' '); do
    if agent_linux_only "$a" && [ "$OS" != "linux" ]; then
      warn "$(lc "$(agent_title "$a") is Linux/WSL only; skipping install" "$(agent_title "$a") 仅支持 Linux/WSL；跳过安装")"
      results+=("SKIP|$a|0"); continue
    fi
    rc=0; install_agent "$a" || rc=$?
    if [ "$rc" -eq 0 ]; then results+=("OK|$a|install"); else
      results+=("FAIL|$a|install")
      [ "$FAIL_FAST" -eq 1 ] && { warn "$(lc 'fail-fast: stopping' 'fail-fast：停止')"; break; }
    fi
  done

  # --- 阶段 2：统一收集凭据 ---
  step "$(lc 'credentials (asked once, shared by all agents)' '凭据（只问一次，所有 agent 共用）')"
  collect_credentials

  # --- 阶段 3：批量配置 ---
  for a in $(printf '%s' "$SELECTED" | tr ',' ' '); do
    rc=0; configure_agent "$a" || rc=$?
    if [ "$rc" -eq 0 ]; then okc=$((okc+1)); else failc=$((failc+1)); results+=("FAIL|$a|config")
      [ "$FAIL_FAST" -eq 1 ] && break
    fi
  done

  # --- 汇总 ---
  printf '\n%s\n' "${BOLD}$(lc 'summary' '汇总')${RESET}" >&2
  printf '%s\n' "${DIM}────────────────────────────────────────────${RESET}" >&2
  local r st a2 ph
  for r in ${results[@]+"${results[@]}"}; do
    st="${r%%|*}"; r="${r#*|}"; a2="${r%%|*}"; ph="${r##*|}"
    if [ "$st" = "OK" ]; then printf '  %s  %-12s %s\n' "${GREEN}✓${RESET}" "$(agent_title "$a2")" "${DIM}$ph${RESET}" >&2
    elif [ "$st" = "SKIP" ]; then printf '  %s  %-12s %s\n' "${YELLOW}-${RESET}" "$(agent_title "$a2")" "${DIM}$(lc 'Linux only, skipped' '仅 Linux，已跳过')${RESET}" >&2
    else printf '  %s  %-12s %s\n' "${RED}✗${RESET}" "$(agent_title "$a2")" "${DIM}$ph${RESET}" >&2; fi
  done
  info "$(lc "$okc configured, $failc failed" "配置成功 $okc 个，失败 $failc 个")"
  [ "$failc" -eq 0 ]
}

main "$@"
