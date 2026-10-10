#!/usr/bin/env bash
# Claude Code Linux 一键安装与自定义 API 配置脚本
# Claude Code Linux one-click installer with a custom Anthropic-compatible API.
#
# 交互与安全实践参考 pi-setup（https://github.com/zxfccmm4/pi-setup）：
#   - 中英双语向导（--lang / CLAUDE_LANG，默认按系统 locale 自动判断）
#   - API Key 逐字符显示 *，回车后回显为 前5位...后5位，摘要同样脱敏
#   - 自动拉取端点模型列表（GET <base>/v1/models，20 秒超时），编号/过滤选择默认模型
#   - 写盘前打印执行计划并确认；写盘前自动生成 <文件>.bak.<时间戳> 备份
set -Eeuo pipefail

PROGRAM_NAME="$(basename "$0")"
NATIVE_INSTALL_URL="https://claude.ai/install.sh"
NODE_MAJOR_REQUIRED=22
MODELS_TIMEOUT=20

BASE_URL="${CLAUDE_BASE_URL:-${ANTHROPIC_BASE_URL:-}}"
AUTH_MODE="${CLAUDE_AUTH_MODE:-auth-token}"
API_SECRET="${CLAUDE_API_KEY:-}"
# 注意：不能从 ANTHROPIC_MODEL 初始化——本脚本第一次运行会把它写进 shell 配置，
# 之后每个新终端都带着旧值，导致第二次运行时交互提示被跳过、旧模型无法更改。
MODEL="${CLAUDE_MODEL:-}"
INSTALL_METHOD="${CLAUDE_INSTALL_METHOD:-npm}"
VERSION="${CLAUDE_VERSION:-latest}"
CONFIG_MODE="${CLAUDE_CONFIG_MODE:-shell}"
AUTO_MODE_SERVER="${CLAUDE_AUTO_MODE_SERVER:-auto}"
LANG_CODE="${CLAUDE_LANG:-}"

AUTH_MODE_EXPLICIT=0
[[ -z "${CLAUDE_AUTH_MODE:-}" ]] || AUTH_MODE_EXPLICIT=1
NON_INTERACTIVE=0
SKIP_NODE=0
SKIP_INSTALL=0
FORCE_INSTALL=0
DRY_RUN=0

# ---------------------------------------------------------------------------
# 语言 / language
# ---------------------------------------------------------------------------
normalize_lang() {
  case "$LANG_CODE" in
    zh|zh-*|*[_-]CN|*[_-]CN.*|*[_-]TW|*[_-]TW.*|*[_-]HK|*[_-]HK.*) LANG_CODE=zh ;;
    *) LANG_CODE=en ;;
  esac
}

if [[ -n "$LANG_CODE" ]]; then
  normalize_lang
else
  # 没有显式指定时按系统 locale 猜测 / guess from the system locale.
  LANG_CODE="${LC_ALL:-${LC_MESSAGES:-${LANG:-}}}"
  case "$LANG_CODE" in
    zh*|*[_-]CN*|*[_-]TW*|*[_-]HK*) LANG_CODE=zh ;;
    *) LANG_CODE=en ;;
  esac
fi

lc() {
  # lc 'English text' '中文文本' —— 按当前语言输出其一。
  if [[ "$LANG_CODE" == "zh" ]]; then printf '%s' "$2"; else printf '%s' "$1"; fi
}

log()  { printf '\033[1;34m[INFO]\033[0m %s\n' "$*"; }
ok()   { printf '\033[1;32m[ OK ]\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33m[WARN]\033[0m %s\n' "$*" >&2; }
die()  { printf '\033[1;31m[ERR ]\033[0m %s\n' "$*" >&2; exit 1; }

# ---------------------------------------------------------------------------
# 终端读取与掩码输入 / tty helpers & masked input
# ---------------------------------------------------------------------------
ECHO_SAVED=""
MODELS_TMP=""
MODELS_ERR=""

restore_echo() {
  if [[ -n "$ECHO_SAVED" ]]; then
    stty "$ECHO_SAVED" < /dev/tty 2>/dev/null || stty echo < /dev/tty 2>/dev/null || true
    ECHO_SAVED=""
  fi
}

cleanup() {
  restore_echo
  if [[ -n "$MODELS_TMP" ]]; then rm -f "$MODELS_TMP"; fi
  if [[ -n "$MODELS_ERR" ]]; then rm -f "$MODELS_ERR"; fi
  return 0
}
trap cleanup EXIT

have_tty() { : 2>/dev/null </dev/tty; }

read_tty() {
  if have_tty; then IFS= read -r "$@" < /dev/tty; else IFS= read -r "$@"; fi
}

require_tty() {
  have_tty && return 0
  die "$(lc 'no interactive terminal available; use --non-interactive with --base-url and --token/--api-key.' \
           '当前没有可用的交互终端；请使用 --non-interactive，并传入 --base-url 和 --token/--api-key。')"
}

mask() {
  local s="$1" n=${#1}
  if [[ "$n" -le 10 ]]; then
    printf '********'
  else
    local tail_start=$((n - 5))
    printf '%s...%s' "${s:0:5}" "${s:tail_start}"
  fi
}

ask() {
  local msg="$1" def="${2-}" val
  if [[ -n "$def" ]]; then printf '%s [%s]: ' "$msg" "$def" >&2; else printf '%s: ' "$msg" >&2; fi
  read_tty val || true
  printf '%s' "${val:-$def}"
}

ask_secret() {
  local msg="$1" val="" masked c
  require_tty
  # 在打印提示之前就关闭终端回显，粘贴也不会泄露；输入时逐字符显示 *。
  ECHO_SAVED="$(stty -g < /dev/tty 2>/dev/null || true)"
  if [[ -n "$ECHO_SAVED" ]]; then stty -echo < /dev/tty 2>/dev/null || true; fi
  printf '%s: ' "$msg" >&2
  while IFS= read -r -n1 c < /dev/tty; do
    case "$c" in
      $'\177'|$'\b')
        if [[ -n "$val" ]]; then val="${val%?}"; printf '\b \b' >&2; fi
        ;;
      ''|$'\n'|$'\r') break ;;
      *) val+="$c"; printf '*' >&2 ;;
    esac
  done
  printf '\n' >&2
  restore_echo
  # 把刚才那行替换成脱敏回显（前5位...后5位）。
  masked="$(mask "$val")"
  printf '\033[A\r\033[K%s: %s\n' "$msg" "$masked" >&2
  printf '%s' "$val"
}

ask_yes() {
  local msg="$1" def="${2:-n}" val
  printf '%s [%s]: ' "$msg" "$def" >&2
  read_tty val || true
  val="${val:-$def}"
  case "$val" in y|Y|yes|YES|Yes) return 0 ;; *) return 1 ;; esac
}

# ---------------------------------------------------------------------------
# 帮助 / usage
# ---------------------------------------------------------------------------
usage_en() {
  cat <<'USAGE'
Usage:
  bash install-claude-code.sh [options]

Options:
  --base-url URL              Custom Anthropic Messages API compatible endpoint
  --api-key KEY               API key/token (alias: --token)
  --token TOKEN               Alias of --api-key
  --auth-mode MODE            auth-token or api-key, default auth-token
                              auth-token -> Authorization: Bearer TOKEN
                              api-key    -> X-Api-Key: KEY
  --model MODEL               Optional; sets ANTHROPIC_MODEL. In the interactive
                              wizard the model list is fetched from the endpoint
                              (GET <base>/v1/models) and can be picked by number.
  --install-method METHOD     npm or native, default npm
  --version VERSION           npm: latest or a specific version;
                              native: latest/stable/specific version
  --config-mode MODE          shell or settings, default shell
                              shell: separate env file loaded by bash/zsh profiles
                              settings: merged into ~/.claude/settings.json
  --auto-mode-server MODE     auto or off, default auto
                              off writes CLAUDE_CODE_AUTO_MODE_SERVER=0 for
                              gateways not yet compatible with the new Auto mode
  --lang en|zh                Wizard/output language (env CLAUDE_LANG;
                              default: auto-detect from the system locale)
  --skip-node                 Skip the Node.js check/install (npm mode only)
  --skip-install              Do not install Claude Code; only update API config
  --force-install             Back up a conflicting entry and reinstall even if
                              Claude Code is already present
  --non-interactive           Non-interactive mode; error out when the
                              Base URL/token is missing
  --dry-run                   Only print actions; install and write nothing
  -h, --help                  Show this help

Interactive:
  bash install-claude-code.sh

Non-interactive:
  bash install-claude-code.sh \
    --base-url "https://gateway.example.com" \
    --token "sk-xxxx" \
    --auth-mode auth-token \
    --non-interactive

Environment variables:
  CLAUDE_BASE_URL="https://gateway.example.com" \
  CLAUDE_API_KEY="sk-xxxx" \
  CLAUDE_AUTH_MODE="auth-token" \
  bash install-claude-code.sh --non-interactive
USAGE
}

usage_zh() {
  cat <<'USAGE'
用法：
  bash install-claude-code.sh [选项]

选项：
  --base-url URL              自定义 Anthropic Messages API 兼容地址
  --api-key KEY               API Key/Token（也可使用 --token）
  --token TOKEN               --api-key 的别名
  --auth-mode MODE            auth-token 或 api-key，默认 auth-token
                              auth-token -> Authorization: Bearer TOKEN
                              api-key    -> X-Api-Key: KEY
  --model MODEL               可选，设置 ANTHROPIC_MODEL；交互式向导会自动
                              拉取端点模型列表（GET <base>/v1/models），
                              支持编号选择和关键词过滤
  --install-method METHOD     npm 或 native，默认 npm
  --version VERSION           npm: latest 或具体版本；native: latest/stable/具体版本
  --config-mode MODE          shell 或 settings，默认 shell
                              shell: 安全写入独立 env 文件，由 bash/zsh 配置加载
                              settings: 合并到 ~/.claude/settings.json
  --auto-mode-server MODE     auto 或 off，默认 auto
                              off: 写入 CLAUDE_CODE_AUTO_MODE_SERVER=0，
                              用于暂时兼容尚未适配新版 Auto mode 的第三方网关
  --lang en|zh                向导与输出语言（环境变量 CLAUDE_LANG；
                              默认按系统 locale 自动判断）
  --skip-node                 不检测/安装 Node.js（仅 npm 安装模式有效）
  --skip-install              不安装 Claude Code，只更新 API 配置
  --force-install             即使检测到 Claude Code，也备份旧入口并重新安装
  --non-interactive           非交互模式，缺少 Base URL/Token 时直接报错
  --dry-run                   只显示操作，不安装或写文件
  -h, --help                  显示帮助

交互式：
  bash install-claude-code.sh

非交互式：
  bash install-claude-code.sh \
    --base-url "https://gateway.example.com" \
    --token "sk-xxxx" \
    --auth-mode auth-token \
    --non-interactive

也可用环境变量：
  CLAUDE_BASE_URL="https://gateway.example.com" \
  CLAUDE_API_KEY="sk-xxxx" \
  CLAUDE_AUTH_MODE="auth-token" \
  bash install-claude-code.sh --non-interactive
USAGE
}

usage() {
  case "$LANG_CODE" in
    zh) usage_zh ;;
    *)  usage_en ;;
  esac
}

# ---------------------------------------------------------------------------
# 参数解析 / argument parsing
# ---------------------------------------------------------------------------
while [[ $# -gt 0 ]]; do
  case "$1" in
    --base-url)
      [[ $# -ge 2 ]] || die "$(lc "$1 requires a value" "$1 缺少参数")"
      BASE_URL="$2"; shift 2 ;;
    --base-url=*) BASE_URL="${1#*=}"; shift ;;
    --api-key|--token)
      [[ $# -ge 2 ]] || die "$(lc "$1 requires a value" "$1 缺少参数")"
      API_SECRET="$2"; shift 2 ;;
    --api-key=*|--token=*) API_SECRET="${1#*=}"; shift ;;
    --auth-mode)
      [[ $# -ge 2 ]] || die "$(lc "$1 requires a value" "$1 缺少参数")"
      AUTH_MODE="$2"; AUTH_MODE_EXPLICIT=1; shift 2 ;;
    --auth-mode=*) AUTH_MODE="${1#*=}"; AUTH_MODE_EXPLICIT=1; shift ;;
    --model)
      [[ $# -ge 2 ]] || die "$(lc "$1 requires a value" "$1 缺少参数")"
      MODEL="$2"; shift 2 ;;
    --model=*) MODEL="${1#*=}"; shift ;;
    --install-method)
      [[ $# -ge 2 ]] || die "$(lc "$1 requires a value" "$1 缺少参数")"
      INSTALL_METHOD="$2"; shift 2 ;;
    --install-method=*) INSTALL_METHOD="${1#*=}"; shift ;;
    --version|--channel)
      [[ $# -ge 2 ]] || die "$(lc "$1 requires a value" "$1 缺少参数")"
      VERSION="$2"; shift 2 ;;
    --version=*|--channel=*) VERSION="${1#*=}"; shift ;;
    --config-mode)
      [[ $# -ge 2 ]] || die "$(lc "$1 requires a value" "$1 缺少参数")"
      CONFIG_MODE="$2"; shift 2 ;;
    --config-mode=*) CONFIG_MODE="${1#*=}"; shift ;;
    --auto-mode-server)
      [[ $# -ge 2 ]] || die "$(lc "$1 requires a value" "$1 缺少参数")"
      AUTO_MODE_SERVER="$2"; shift 2 ;;
    --auto-mode-server=*) AUTO_MODE_SERVER="${1#*=}"; shift ;;
    --lang)
      [[ $# -ge 2 ]] || die "$(lc "$1 requires a value (en or zh)" "$1 缺少参数（en 或 zh）")"
      LANG_CODE="$2"; normalize_lang; shift 2 ;;
    --lang=*) LANG_CODE="${1#*=}"; normalize_lang; shift ;;
    --skip-node) SKIP_NODE=1; shift ;;
    --skip-install) SKIP_INSTALL=1; shift ;;
    --force-install) FORCE_INSTALL=1; shift ;;
    --non-interactive) NON_INTERACTIVE=1; shift ;;
    --dry-run) DRY_RUN=1; shift ;;
    -h|--help) usage; exit 0 ;;
    *) die "$(lc "unknown option: $1 (see --help)" "未知参数：$1（使用 --help 查看帮助）")" ;;
  esac
done

[[ "$(uname -s)" == "Linux" ]] || die "$(lc 'this script only supports Linux/WSL.' '此脚本仅适用于 Linux/WSL。')"
case "$(uname -m)" in
  x86_64|amd64|aarch64|arm64) ;;
  *) die "$(lc "unsupported CPU architecture: $(uname -m); only x64 and ARM64 are supported." "不支持的 CPU 架构：$(uname -m)；仅支持 x64 和 ARM64。")" ;;
esac

case "$AUTH_MODE" in
  auth-token|api-key) ;;
  *) die "$(lc '--auth-mode must be auth-token or api-key.' '--auth-mode 只能是 auth-token 或 api-key')" ;;
esac
case "$INSTALL_METHOD" in
  npm|native) ;;
  *) die "$(lc '--install-method must be npm or native.' '--install-method 只能是 npm 或 native')" ;;
esac
case "$CONFIG_MODE" in
  shell|settings) ;;
  *) die "$(lc '--config-mode must be shell or settings.' '--config-mode 只能是 shell 或 settings')" ;;
esac
case "$AUTO_MODE_SERVER" in
  auto|off) ;;
  *) die "$(lc '--auto-mode-server must be auto or off.' '--auto-mode-server 只能是 auto 或 off')" ;;
esac
[[ "$VERSION" =~ ^(latest|stable|[0-9]+\.[0-9]+\.[0-9]+)$ ]] || \
  die "$(lc '--version must be latest, stable, or a specific version (e.g. 2.1.198).' '--version 必须是 latest、stable 或具体版本号（例如 2.1.198）')"
if [[ "$INSTALL_METHOD" == "npm" && "$VERSION" == "stable" ]]; then
  die "$(lc 'npm installs do not use the stable channel; use --version latest/<version> or --install-method native.' 'npm 安装模式不使用 stable 频道；请改用 --version latest/具体版本，或 --install-method native。')"
fi

# 命令行参数解析完毕后，再按最终认证方式读取对应的官方环境变量。
if [[ -z "$API_SECRET" ]]; then
  if [[ "$AUTH_MODE" == "api-key" ]]; then
    API_SECRET="${ANTHROPIC_API_KEY:-}"
  else
    API_SECRET="${ANTHROPIC_AUTH_TOKEN:-}"
  fi
fi

# ---------------------------------------------------------------------------
# 模型列表拉取与选择 / model list fetch & picker
# ---------------------------------------------------------------------------
MODEL_IDS=()
MODEL_NAMES=()
VIEW_IDS=()
VIEW_NAMES=()
FETCH_ERROR=""

fetch_models() {
  FETCH_ERROR=""
  MODEL_IDS=()
  MODEL_NAMES=()
  [[ -n "$BASE_URL" && -n "$API_SECRET" ]] || return 1
  command -v curl >/dev/null 2>&1 || { FETCH_ERROR="curl $(lc 'not found' '未安装')"; return 1; }

  local url
  url="${BASE_URL%/}/v1/models"
  if [[ -z "$MODELS_TMP" ]]; then
    MODELS_TMP="$(mktemp "${TMPDIR:-/tmp}/claude-models.XXXXXX")"
    MODELS_ERR="${MODELS_TMP}.err"
  fi

  local -a args=(--connect-timeout 10 --max-time "$MODELS_TIMEOUT" -fsS)
  if [[ "$AUTH_MODE" == "api-key" ]]; then
    args+=(-H "x-api-key: ${API_SECRET}")
  else
    args+=(-H "Authorization: Bearer ${API_SECRET}")
  fi
  args+=(-H "anthropic-version: 2023-06-01" -H "accept: application/json" "$url" -o "$MODELS_TMP")

  if ! curl "${args[@]}" 2>"$MODELS_ERR"; then
    FETCH_ERROR="$(grep -v '^[[:space:]]*$' "$MODELS_ERR" 2>/dev/null | tail -n 1 || true)"
    [[ -n "$FETCH_ERROR" ]] || FETCH_ERROR="$(lc 'HTTP request failed' 'HTTP 请求失败')"
    return 1
  fi

  local line id name
  if command -v python3 >/dev/null 2>&1; then
    while IFS= read -r line; do
      [[ -n "$line" ]] || continue
      id="${line%%$'\t'*}"
      if [[ "$id" == "$line" ]]; then name="$id"; else name="${line#*$'\t'}"; fi
      MODEL_IDS+=("$id")
      MODEL_NAMES+=("$name")
    done < <(python3 - "$MODELS_TMP" 2>"$MODELS_ERR" <<'PY'
import json
import sys
import pathlib

try:
    data = json.loads(pathlib.Path(sys.argv[1]).read_text(encoding="utf-8", errors="replace"))
except Exception as exc:
    raise SystemExit(f"invalid JSON: {exc}")

items = []
if isinstance(data, dict):
    items = data.get("data") or data.get("models") or []
elif isinstance(data, list):
    items = data

seen = set()
for it in items:
    if isinstance(it, str):
        mid, name = it, it
    elif isinstance(it, dict):
        mid = it.get("id") or it.get("name") or ""
        if not mid:
            continue
        name = it.get("display_name") or it.get("displayLabel") or it.get("name") or mid
    else:
        continue
    if mid in seen:
        continue
    seen.add(mid)
    print(f"{mid}\t{name}")
PY
)
  elif command -v node >/dev/null 2>&1; then
    while IFS= read -r line; do
      [[ -n "$line" ]] || continue
      id="${line%%$'\t'*}"
      if [[ "$id" == "$line" ]]; then name="$id"; else name="${line#*$'\t'}"; fi
      MODEL_IDS+=("$id")
      MODEL_NAMES+=("$name")
    done < <(node -e '
const fs = require("fs");
let data;
try { data = JSON.parse(fs.readFileSync(process.argv[1], "utf8")); }
catch (e) { console.error("invalid JSON: " + e.message); process.exit(1); }
let items = [];
if (Array.isArray(data)) items = data;
else if (data && typeof data === "object") items = data.data || data.models || [];
const seen = new Set();
for (const it of items) {
  let mid, name;
  if (typeof it === "string") { mid = it; name = it; }
  else if (it && typeof it === "object") {
    mid = it.id || it.name || "";
    if (!mid) continue;
    name = it.display_name || it.displayLabel || it.name || mid;
  } else { continue; }
  if (seen.has(mid)) continue;
  seen.add(mid);
  console.log(mid + "\t" + name);
}
' "$MODELS_TMP" 2>"$MODELS_ERR")
  else
    FETCH_ERROR="$(lc 'python3/node not available to parse the model list' '缺少 python3/node，无法解析模型列表')"
    return 1
  fi

  if [[ ${#MODEL_IDS[@]} -eq 0 ]]; then
    FETCH_ERROR="$(grep -v '^[[:space:]]*$' "$MODELS_ERR" 2>/dev/null | tail -n 1 || true)"
    [[ -n "$FETCH_ERROR" ]] || FETCH_ERROR="$(lc 'no models in the response' '响应中没有模型')"
    return 1
  fi
  return 0
}

build_view() {
  local filter i hay
  filter="$(printf '%s' "$1" | tr '[:upper:]' '[:lower:]')"
  VIEW_IDS=()
  VIEW_NAMES=()
  for ((i = 0; i < ${#MODEL_IDS[@]}; i++)); do
    hay="$(printf '%s %s' "${MODEL_IDS[$i]}" "${MODEL_NAMES[$i]}" | tr '[:upper:]' '[:lower:]')"
    if [[ -n "$filter" ]]; then
      case "$hay" in *"$filter"*) : ;; *) continue ;; esac
    fi
    VIEW_IDS+=("${MODEL_IDS[$i]}")
    VIEW_NAMES+=("${MODEL_NAMES[$i]}")
  done
  [[ ${#VIEW_IDS[@]} -gt 0 ]]
}

print_view() {
  local max="${1:-15}" i total=${#VIEW_IDS[@]}
  for ((i = 0; i < total; i++)); do
    if [[ $((i + 1)) -le "$max" ]]; then
      printf '   %d) %s' "$((i + 1))" "${VIEW_IDS[$i]}" >&2
      if [[ "${VIEW_NAMES[$i]}" != "${VIEW_IDS[$i]}" ]]; then
        printf ' - %s' "${VIEW_NAMES[$i]}" >&2
      fi
      printf '\n' >&2
    fi
  done
  if [[ "$total" -gt "$max" ]]; then
    printf '   ... %s\n' "$(lc "$((total - max)) more - type text to filter, or r for the full list" "还有 $((total - max)) 个 - 输入文字过滤，或输入 r 显示全部")" >&2
  fi
  printf '%s\n' "$(lc "   ($total models)" "   （共 $total 个模型）")" >&2
}

ask_model_manual() {
  local current="$1" v
  if [[ -n "$current" ]]; then
    # 第一次运行写入的 ANTHROPIC_MODEL 已在当前 shell 生效；必须重新询问，
    # 否则第二次运行会静默沿用旧模型，用户无法更改。输入 - 取消固定。
    v="$(ask "$(lc "default model (Enter = keep ${current}, '-' to unpin)" "默认模型（回车沿用 ${current}，输入 - 取消固定）")" "$current")"
  else
    v="$(ask "$(lc 'default model (optional)' '默认模型（可留空）')" '')"
  fi
  [[ "$v" == "-" ]] && v=""
  printf '%s' "$v"
}

# 交互式选择默认模型；把选中的模型 id 打印到 stdout，跳过时返回 1。
pick_default_model() {
  local current="$1" input filter="" max=15 manual
  [[ ${#MODEL_IDS[@]} -gt 0 ]] || return 1
  while :; do
    if ! build_view "$filter"; then
      warn "$(lc 'nothing matched that filter' '没有匹配的模型')"
      filter=""
      continue
    fi
    printf '\n%s\n' "$(lc 'pick the default model:' '选择默认模型：')" >&2
    print_view "$max"
    input="$(ask "$(lc 'number / m = type an id / text to filter / r = all / Enter = skip' '编号 / m 手动输入 / 过滤词 / r 全部 / 回车跳过')" '')"
    case "$input" in
      '') return 1 ;;
      m|M)
        manual="$(ask_model_manual "$current")"
        if [[ -z "$manual" ]]; then return 1; fi
        printf '%s' "$manual"
        return 0 ;;
      r|R|all|ALL) max=200; continue ;;
      *[!0-9]*) filter="$input"; continue ;;
    esac
    if [[ "$input" -ge 1 && "$input" -le ${#VIEW_IDS[@]} ]]; then
      printf '%s' "${VIEW_IDS[$((input - 1))]}"
      return 0
    fi
    warn "$(lc "invalid number '$input'" "无效编号 '$input'")"
  done
}

choose_model_interactive() {
  local current="${ANTHROPIC_MODEL:-}" picked=""
  if [[ -z "$MODEL" ]]; then
    if [[ -n "$current" ]]; then
      log "$(lc "current default model: $current" "当前默认模型：$current")"
    fi
    log "$(lc 'fetching the model list from the endpoint...' '正在从端点拉取模型列表……')"
    if fetch_models; then
      log "$(lc "found ${#MODEL_IDS[@]} models" "共获取到 ${#MODEL_IDS[@]} 个模型")"
      picked="$(pick_default_model "$current")" || true
      # 直接回车跳过 = 保持现状（沿用已固定的模型或不固定）。
      if [[ -z "$picked" ]]; then picked="$current"; fi
    else
      warn "$(lc 'could not fetch the model list from the endpoint' '无法从该端点拉取模型列表')"
      if [[ -n "$FETCH_ERROR" ]]; then printf '   %s\n' "$FETCH_ERROR" >&2; fi
      warn "$(lc 'falling back to typing the model id by hand' '改用手动输入模型 id')"
      picked="$(ask_model_manual "$current")"
    fi
    MODEL="$picked"
  fi
}

# ---------------------------------------------------------------------------
# 交互式向导 / interactive wizard
# ---------------------------------------------------------------------------
choose_language() {
  local v
  printf '0) Language / 语言:  1) English  2) 简体中文\n' >&2
  v="$(ask "$(lc '   choose [1-2]' '   请选择 [1-2]')" "$(if [[ "$LANG_CODE" == "zh" ]]; then printf '2'; else printf '1'; fi)")"
  case "$v" in
    2) LANG_CODE=zh ;;
    1) LANG_CODE=en ;;
  esac
  log "$(lc 'language: English' '语言：简体中文')"
}

# 写盘/安装前的执行计划确认；回答 n 直接退出且不做任何修改。
confirm_plan() {
  local auth_desc env_hint
  if [[ "$AUTH_MODE" == "auth-token" ]]; then auth_desc="Authorization: Bearer"; else auth_desc="X-Api-Key"; fi
  printf '\n%s\n' "$(lc 'Plan:' '执行计划：')"
  printf '  %s : %s\n' "$(lc 'Base URL' 'Base URL')" "$BASE_URL"
  printf '  %s : %s\n' "$(lc 'Token   ' '密钥    ')" "$(mask "$API_SECRET")"
  printf '  %s : %s (%s)\n' "$(lc 'Auth    ' '认证    ')" "$AUTH_MODE" "$auth_desc"
  if [[ -n "$MODEL" ]]; then
    printf '  %s : %s\n' "$(lc 'Model   ' '模型    ')" "$MODEL"
  else
    printf '  %s : %s\n' "$(lc 'Model   ' '模型    ')" "$(lc '(not pinned)' '（不固定）')"
  fi
  if [[ $SKIP_INSTALL -eq 1 ]]; then
    printf '  %s : %s\n' "$(lc 'Install ' '安装    ')" "$(lc 'skip (--skip-install)' '跳过（--skip-install）')"
  else
    printf '  %s : %s (%s)\n' "$(lc 'Install ' '安装    ')" "$INSTALL_METHOD" "$VERSION"
  fi
  if [[ "$CONFIG_MODE" == "shell" ]]; then
    env_hint="${XDG_CONFIG_HOME:-$HOME/.config}/claude-code/env"
  else
    env_hint="${CLAUDE_CONFIG_DIR:-$HOME/.claude}/settings.json"
  fi
  printf '  %s : %s\n' "$(lc 'Config  ' '配置    ')" "$env_hint"
  if [[ "$AUTO_MODE_SERVER" == "off" ]]; then
    printf '  %s : %s\n' "$(lc 'Auto mode' 'Auto mode')" "CLAUDE_CODE_AUTO_MODE_SERVER=0"
  fi
  printf '\n'
  if ! ask_yes "$(lc 'Proceed?' '继续执行？')" "y"; then
    ok "$(lc 'Cancelled; nothing was changed.' '已取消，未做任何修改。')"
    exit 0
  fi
}

if [[ $NON_INTERACTIVE -eq 0 ]]; then
  if ! have_tty; then
    # curl ... | bash 会占用标准输入来读取脚本本身，因此交互输入必须从控制终端读取。
    if [[ -n "$BASE_URL" && -n "$API_SECRET" ]]; then
      warn "$(lc 'no interactive terminal; all inputs provided - continuing without prompts.' '无交互终端；所需参数已齐全，跳过交互确认继续。')"
      NON_INTERACTIVE=1
    else
      die "$(lc 'no interactive terminal available; use --non-interactive with --base-url and --token/--api-key.' '当前没有可用的交互终端；请使用 --non-interactive，并传入 --base-url 和 --token/--api-key。')"
    fi
  fi
fi

if [[ $NON_INTERACTIVE -eq 0 ]]; then
  printf '\n%s\n' "$(lc 'Claude Code install / configure' 'Claude Code 安装 / 配置')"
  printf '%s\n' '--------------------------------'

  choose_language
  printf '\n%s\n' "$(lc 'step-by-step setup (press Enter to accept the [default])' '逐步配置（直接回车 = 采用 [默认值]）')" >&2

  if [[ -z "$BASE_URL" ]]; then
    BASE_URL="$(ask "$(lc '1) Base URL (e.g. https://gateway.example.com)' '1) Base URL（例如 https://gateway.example.com）')" '')"
  fi
  if [[ $AUTH_MODE_EXPLICIT -eq 0 ]]; then
    printf '%s\n' "$(lc '2) Auth mode:' '2) 认证方式：')" >&2
    printf '  1) auth-token -> Authorization: Bearer (%s)\n' "$(lc 'gateways; default' '代理网关常用，默认')" >&2
    printf '  2) api-key    -> X-Api-Key (%s)\n' "$(lc 'official Anthropic API' 'Anthropic 官方 API 常用')" >&2
    auth_choice="$(ask "$(lc '   choose [1-2]' '   请选择 [1-2]')" '1')"
    case "$auth_choice" in
      1) AUTH_MODE="auth-token" ;;
      2) AUTH_MODE="api-key" ;;
      *) die "$(lc "invalid choice: $auth_choice" "无效选择：$auth_choice")" ;;
    esac
  fi
  # 先确定认证方式再读取密钥：拉取模型列表时要用正确的请求头。
  if [[ -z "$API_SECRET" ]]; then
    API_SECRET="$(ask_secret "$(lc '3) API Key / Token' '3) API Key/Token')")"
    printf '\n' >&2
  fi
  printf '%s\n' "$(lc '4) Default model' '4) 默认模型')" >&2
  choose_model_interactive
  printf '\n' >&2
fi

# 非交互模式且未显式传模型时，沿用环境中已有的 ANTHROPIC_MODEL，保持重跑幂等。
if [[ $NON_INTERACTIVE -eq 1 && -z "$MODEL" ]]; then
  MODEL="${ANTHROPIC_MODEL:-}"
fi

[[ -n "$BASE_URL" ]] || die "$(lc 'missing Base URL; use --base-url or CLAUDE_BASE_URL.' '缺少 Base URL；请使用 --base-url 或 CLAUDE_BASE_URL。')"
[[ "$BASE_URL" =~ ^https?://[^[:space:]]+$ ]] || die "$(lc 'Base URL must start with http:// or https:// and contain no spaces.' 'Base URL 必须以 http:// 或 https:// 开头，且不能包含空格。')"
BASE_URL="${BASE_URL%/}"
[[ -n "$API_SECRET" ]] || die "$(lc 'missing API key/token; use --token/--api-key or CLAUDE_API_KEY.' '缺少 API Key/Token；请使用 --token/--api-key 或 CLAUDE_API_KEY。')"
if [[ "$BASE_URL" != https://* ]]; then
  warn "$(lc 'Base URL uses plain HTTP; prefer HTTPS in production.' '当前 Base URL 使用明文 HTTP；生产环境请改用 HTTPS。')"
fi

# 交互模式下写盘/安装前最后确认一次。
if [[ $NON_INTERACTIVE -eq 0 ]]; then
  confirm_plan
fi

# ---------------------------------------------------------------------------
# 安装 / installation
# ---------------------------------------------------------------------------
run() {
  if [[ $DRY_RUN -eq 1 ]]; then
    printf '[DRY-RUN]'
    printf ' %q' "$@"
    printf '\n'
  else
    "$@"
  fi
}

as_root() {
  if [[ ${EUID:-$(id -u)} -eq 0 ]]; then
    run "$@"
  elif command -v sudo >/dev/null 2>&1; then
    run sudo "$@"
  else
    die "$(lc 'this step needs root but sudo is unavailable; run as root or install the dependency first.' '此操作需要 root 权限，但系统没有 sudo；请用 root 运行或先安装依赖。')"
  fi
}

install_curl_if_needed() {
  command -v curl >/dev/null 2>&1 && return 0
  log "$(lc 'curl not found; installing...' '未检测到 curl，正在安装……')"
  if command -v apt-get >/dev/null 2>&1; then
    as_root apt-get update
    as_root apt-get install -y curl ca-certificates
  elif command -v dnf >/dev/null 2>&1; then
    as_root dnf install -y curl ca-certificates
  elif command -v yum >/dev/null 2>&1; then
    as_root yum install -y curl ca-certificates
  elif command -v apk >/dev/null 2>&1; then
    as_root apk add --no-cache curl ca-certificates
  elif command -v pacman >/dev/null 2>&1; then
    as_root pacman -Sy --noconfirm curl ca-certificates
  elif command -v zypper >/dev/null 2>&1; then
    as_root zypper --non-interactive install curl ca-certificates
  else
    die "$(lc 'unknown package manager; install curl and ca-certificates manually.' '无法识别包管理器；请先手动安装 curl 和 ca-certificates。')"
  fi
}

node_major() {
  command -v node >/dev/null 2>&1 || return 1
  node --version 2>/dev/null | sed -E 's/^v([0-9]+).*/\1/'
}

node_is_compatible() {
  major="$(node_major 2>/dev/null || true)"
  [[ "$major" =~ ^[0-9]+$ ]] && [[ "$major" -ge "$NODE_MAJOR_REQUIRED" ]]
}

install_node() {
  if node_is_compatible; then
    ok "$(lc "Node.js $(node --version) detected; skipping install." "已检测到 Node.js $(node --version)，跳过安装。")"
    command -v npm >/dev/null 2>&1 || die "$(lc 'Node.js found but npm is missing; install npm first.' '已找到 Node.js，但没有 npm；请先安装 npm。')"
    return 0
  fi

  old_node="$(node --version 2>/dev/null || printf '%s' "$(lc 'not installed' '未安装')")"
  log "$(lc "current Node.js: ${old_node}; npm Claude Code requires Node.js >= ${NODE_MAJOR_REQUIRED}." "当前 Node.js：${old_node}；npm 版 Claude Code 当前要求 Node.js >= ${NODE_MAJOR_REQUIRED}。")"
  install_curl_if_needed

  if command -v apt-get >/dev/null 2>&1; then
    setup_url="https://deb.nodesource.com/setup_${NODE_MAJOR_REQUIRED}.x"
    setup_file="$(mktemp)"
    if [[ $DRY_RUN -eq 1 ]]; then
      printf '[DRY-RUN] curl -fsSL %q -o <tmpfile>\n' "$setup_url"
      printf '[DRY-RUN] sudo bash <tmpfile>\n'
      printf '[DRY-RUN] sudo apt-get install -y nodejs\n'
      rm -f "$setup_file"
      return 0
    fi
    curl --proto '=https' --tlsv1.2 -fsSL "$setup_url" -o "$setup_file"
    as_root bash "$setup_file"
    rm -f "$setup_file"
    as_root apt-get install -y nodejs
  elif command -v dnf >/dev/null 2>&1 || command -v yum >/dev/null 2>&1; then
    setup_url="https://rpm.nodesource.com/setup_${NODE_MAJOR_REQUIRED}.x"
    setup_file="$(mktemp)"
    if [[ $DRY_RUN -eq 1 ]]; then
      printf '[DRY-RUN] curl -fsSL %q -o <tmpfile>\n' "$setup_url"
      printf '[DRY-RUN] sudo %s install -y nodejs\n' "$(if command -v dnf >/dev/null 2>&1; then printf 'dnf'; else printf 'yum'; fi)"
      rm -f "$setup_file"
      return 0
    fi
    curl --proto '=https' --tlsv1.2 -fsSL "$setup_url" -o "$setup_file"
    as_root bash "$setup_file"
    rm -f "$setup_file"
    if command -v dnf >/dev/null 2>&1; then as_root dnf install -y nodejs; else as_root yum install -y nodejs; fi
  elif command -v apk >/dev/null 2>&1; then
    as_root apk add --no-cache nodejs npm
  elif command -v pacman >/dev/null 2>&1; then
    as_root pacman -Sy --noconfirm nodejs npm
  else
    die "$(lc "cannot install Node.js automatically. Install Node.js >= ${NODE_MAJOR_REQUIRED} and npm manually, or use --install-method native." "无法自动安装 Node.js。请手动安装 Node.js >= ${NODE_MAJOR_REQUIRED} 和 npm 后重试，或使用 --install-method native。")"
  fi

  [[ $DRY_RUN -eq 1 ]] && return 0
  hash -r
  node_is_compatible || die "$(lc "Node.js is still older than ${NODE_MAJOR_REQUIRED} after install: $(node --version 2>/dev/null || printf 'not found')." "Node.js 安装后版本仍低于 ${NODE_MAJOR_REQUIRED}：$(node --version 2>/dev/null || printf '未找到')。")"
  command -v npm >/dev/null 2>&1 || die "$(lc 'Node.js installed but npm not found.' 'Node.js 已安装，但未找到 npm。')"
  ok "$(lc "Node.js ready: $(node --version); npm $(npm --version)." "Node.js 已就绪：$(node --version)；npm $(npm --version)。")"
}

shell_quote() {
  # POSIX shell 安全单引号：abc'def -> 'abc'\''def'
  value="$1"
  printf "'"
  while [[ "$value" == *"'"* ]]; do
    head="${value%%\'*}"
    printf "%s'\\\\''" "$head"
    value="${value#*\'}"
  done
  printf "%s'" "$value"
}

ensure_local_bin_path() {
  bin_dir="$HOME/.local/bin"
  marker="# Claude Code PATH (managed by $PROGRAM_NAME)"
  run mkdir -p "$bin_dir"

  case ":$PATH:" in
    *":$bin_dir:"*) return 0 ;;
  esac

  for profile in "$HOME/.bashrc" "$HOME/.bash_profile" "$HOME/.zshrc"; do
    if [[ $DRY_RUN -eq 1 ]]; then
      log "$(lc "will add $bin_dir to PATH in $profile" "将把 $bin_dir 加入 $profile 的 PATH。")"
    else
      touch "$profile"
      if ! grep -Fq "$marker" "$profile" 2>/dev/null; then
        {
          printf '\n%s\n' "$marker"
          # shellcheck disable=SC2016  # 保留字面量 $PATH，供新 shell 展开。
          printf 'export PATH=%s:"$PATH"\n' "$(shell_quote "$bin_dir")"
        } >> "$profile"
      fi
    fi
  done
  export PATH="$bin_dir:$PATH"
}

install_claude_npm() {
  ensure_local_bin_path

  local_claude="$HOME/.local/bin/claude"
  existing_claude=""
  if [[ -x "$local_claude" ]]; then
    existing_claude="$local_claude"
  elif command -v claude >/dev/null 2>&1; then
    existing_claude="$(command -v claude)"
  fi

  if [[ -n "$existing_claude" && $FORCE_INSTALL -eq 0 ]]; then
    if existing_version="$($existing_claude --version 2>/dev/null)"; then
      ok "$(lc "Claude Code ${existing_version:-$existing_claude} detected; skipping reinstall." "已检测到 Claude Code ${existing_version:-$existing_claude}，跳过重复安装。")"
      log "$(lc 'to force an update/reinstall, run again with --force-install.' '如需强制更新/重装，请重新运行并添加 --force-install。')"
      return 0
    fi
    warn "$(lc "found a broken Claude Code entry: $existing_claude; continuing with install." "检测到无法正常运行的 Claude Code 入口：$existing_claude；将继续安装。")"
  fi

  [[ $SKIP_NODE -eq 1 ]] || install_node
  if [[ $DRY_RUN -eq 0 ]]; then
    command -v node >/dev/null 2>&1 || die "$(lc 'Node.js not found; remove --skip-node or install it manually.' '未找到 Node.js；请取消 --skip-node 或先手动安装。')"
    command -v npm >/dev/null 2>&1 || die "$(lc 'npm not found; remove --skip-node or install it manually.' '未找到 npm；请取消 --skip-node 或先手动安装。')"
  fi

  # npm 遇到原生安装器或旧安装遗留的同名入口时会报 EEXIST。
  # 不直接删除用户文件，而是先备份，便于需要时恢复。
  if [[ -e "$local_claude" || -L "$local_claude" ]]; then
    backup_path="${local_claude}.backup.$(date +%Y%m%d-%H%M%S).$$"
    warn "$(lc "conflicting entry $local_claude found; backing it up to $backup_path." "发现冲突入口 $local_claude，将备份为 $backup_path。")"
    run mv "$local_claude" "$backup_path"
  fi

  package="@anthropic-ai/claude-code@$VERSION"
  log "$(lc "installing ${package} via npm..." "正在通过 npm 安装 ${package}……")"
  run npm install --global --prefix "$HOME/.local" "$package"
}

install_claude_native() {
  install_curl_if_needed
  log "$(lc "installing Claude Code via the official native installer (${VERSION})..." "正在通过 Anthropic 官方原生安装器安装 Claude Code（${VERSION}）……")"
  if [[ $DRY_RUN -eq 1 ]]; then
    printf '[DRY-RUN] curl -fsSL %q -o <tmpfile>\n' "$NATIVE_INSTALL_URL"
    printf '[DRY-RUN] bash <tmpfile> %q\n' "$VERSION"
    return 0
  fi
  temp_dir="$(mktemp -d)"
  installer="$temp_dir/claude-install.sh"
  curl --proto '=https' --tlsv1.2 -fsSL "$NATIVE_INSTALL_URL" -o "$installer"
  [[ -s "$installer" ]] || { rm -rf "$temp_dir"; die "$(lc 'official installer download failed or is empty.' '官方安装脚本下载失败或内容为空。')"; }
  bash "$installer" "$VERSION"
  rm -rf "$temp_dir"
}

# ---------------------------------------------------------------------------
# 写配置 / write configuration
# ---------------------------------------------------------------------------
backup_file() {
  # 写盘前把已有文件备份为 <文件>.bak.<时间戳>，便于回滚。
  local f="$1" backup
  [[ -f "$f" ]] || return 1
  backup="${f}.bak.$(date +%Y%m%d-%H%M%S)"
  if ! run cp -p "$f" "$backup"; then
    warn "$(lc "could not back up $f; continuing without a backup" "无法备份 $f；将继续执行（不生成备份）")"
    return 0
  fi
  log "$(lc "backed up $f -> $backup" "已备份 $f -> $backup")"
  return 0
}

write_shell_config() {
  config_dir="${XDG_CONFIG_HOME:-$HOME/.config}/claude-code"
  env_file="$config_dir/env"
  marker="# Claude Code custom API (managed by $PROGRAM_NAME)"

  if [[ $DRY_RUN -eq 1 ]]; then
    log "$(lc "will write ${env_file} and load it from ~/.bashrc, ~/.bash_profile, ~/.zshrc (existing file gets a .bak backup first)." "将写入 ${env_file}，并让 ~/.bashrc、~/.bash_profile、~/.zshrc 加载它（已有文件先备份 .bak）。")"
    return 0
  fi

  backup_file "$env_file" || true
  mkdir -p "$config_dir"
  chmod 700 "$config_dir"
  umask 077
  {
    printf '%s\n' "$marker"
    # 让“source env”同时刷新 Claude Code 的用户级安装路径，避免当前 shell 找不到命令。
    # shellcheck disable=SC2016  # 变量需保留到用户 source 配置时再展开。
    printf '%s\n' 'case ":${PATH:-}:" in' '  *:"$HOME/.local/bin":*) ;;' '  *) export PATH="$HOME/.local/bin:${PATH:-}" ;;' 'esac'
    printf 'export ANTHROPIC_BASE_URL=%s\n' "$(shell_quote "$BASE_URL")"
    if [[ "$AUTH_MODE" == "auth-token" ]]; then
      printf 'export ANTHROPIC_AUTH_TOKEN=%s\n' "$(shell_quote "$API_SECRET")"
      printf 'unset ANTHROPIC_API_KEY\n'
    else
      printf 'export ANTHROPIC_API_KEY=%s\n' "$(shell_quote "$API_SECRET")"
      printf 'unset ANTHROPIC_AUTH_TOKEN\n'
    fi
    if [[ -n "$MODEL" ]]; then
      printf 'export ANTHROPIC_MODEL=%s\n' "$(shell_quote "$MODEL")"
    else
      printf 'unset ANTHROPIC_MODEL\n'
    fi
    if [[ "$AUTO_MODE_SERVER" == "off" ]]; then
      printf 'export CLAUDE_CODE_AUTO_MODE_SERVER=0\n'
    else
      printf 'unset CLAUDE_CODE_AUTO_MODE_SERVER\n'
    fi
  } > "$env_file"
  chmod 600 "$env_file"

  for profile in "$HOME/.bashrc" "$HOME/.bash_profile" "$HOME/.zshrc"; do
    touch "$profile"
    if ! grep -Fq "$marker" "$profile" 2>/dev/null; then
      {
        printf '\n%s\n' "$marker"
        printf '[ -f %s ] && . %s\n' "$(shell_quote "$env_file")" "$(shell_quote "$env_file")"
      } >> "$profile"
    fi
  done
  ok "$(lc "API config saved to ${env_file} (mode 600) and wired into bash/zsh." "API 配置已保存到 ${env_file}（权限 600），并已接入 bash/zsh。")"
}

write_settings_config() {
  settings_dir="${CLAUDE_CONFIG_DIR:-$HOME/.claude}"
  settings_file="$settings_dir/settings.json"

  if [[ $DRY_RUN -eq 1 ]]; then
    log "$(lc "will merge config into ${settings_file} and chmod it to 600 (a .bak backup is made first)." "将合并配置到 ${settings_file}，并将权限设为 600（先备份 .bak）。")"
    return 0
  fi
  if ! command -v python3 >/dev/null 2>&1; then
    warn "$(lc 'python3 not found; cannot merge JSON safely - falling back to the shell config.' '未找到 python3，无法安全合并 JSON；自动改用 shell 配置。')"
    write_shell_config
    return 0
  fi

  backup_file "$settings_file" || true
  mkdir -p "$settings_dir"
  chmod 700 "$settings_dir" 2>/dev/null || true
  umask 077
  CLAUDE_CFG_BASE_URL="$BASE_URL" \
  CLAUDE_CFG_SECRET="$API_SECRET" \
  CLAUDE_CFG_AUTH_MODE="$AUTH_MODE" \
  CLAUDE_CFG_MODEL="$MODEL" \
  CLAUDE_CFG_AUTO_MODE_SERVER="$AUTO_MODE_SERVER" \
  python3 - "$settings_file" <<'PY'
import json
import os
import pathlib
import sys
import tempfile

path = pathlib.Path(sys.argv[1]).expanduser()
if path.exists() and path.stat().st_size:
    try:
        data = json.loads(path.read_text(encoding="utf-8"))
    except Exception as exc:
        raise SystemExit(f"existing config is not valid JSON; left unchanged / 现有配置不是有效 JSON，未做修改：{path}: {exc}")
    if not isinstance(data, dict):
        raise SystemExit(f"existing config root is not a JSON object; left unchanged / 现有配置根节点不是 JSON 对象，未做修改：{path}")
else:
    data = {}

env = data.setdefault("env", {})
if not isinstance(env, dict):
    raise SystemExit(f"'env' in the existing config is not a JSON object; left unchanged / 现有配置中的 env 不是 JSON 对象，未做修改：{path}")
env["ANTHROPIC_BASE_URL"] = os.environ["CLAUDE_CFG_BASE_URL"]
secret = os.environ["CLAUDE_CFG_SECRET"]
if os.environ["CLAUDE_CFG_AUTH_MODE"] == "auth-token":
    env["ANTHROPIC_AUTH_TOKEN"] = secret
    env.pop("ANTHROPIC_API_KEY", None)
else:
    env["ANTHROPIC_API_KEY"] = secret
    env.pop("ANTHROPIC_AUTH_TOKEN", None)
model = os.environ.get("CLAUDE_CFG_MODEL", "")
if model:
    env["ANTHROPIC_MODEL"] = model
else:
    env.pop("ANTHROPIC_MODEL", None)
if os.environ.get("CLAUDE_CFG_AUTO_MODE_SERVER") == "off":
    env["CLAUDE_CODE_AUTO_MODE_SERVER"] = "0"
else:
    env.pop("CLAUDE_CODE_AUTO_MODE_SERVER", None)

path.parent.mkdir(parents=True, exist_ok=True)
fd, tmp = tempfile.mkstemp(prefix="settings.", suffix=".json", dir=str(path.parent))
try:
    with os.fdopen(fd, "w", encoding="utf-8") as f:
        json.dump(data, f, ensure_ascii=False, indent=2)
        f.write("\n")
        f.flush()
        os.fsync(f.fileno())
    os.chmod(tmp, 0o600)
    os.replace(tmp, path)
    os.chmod(path, 0o600)
finally:
    if os.path.exists(tmp):
        os.unlink(tmp)
PY
  ok "$(lc "API config merged into ${settings_file} (mode 600)." "API 配置已合并到 ${settings_file}（权限 600）。")"
}

mark_onboarding_complete() {
  if [[ -n "${CLAUDE_CONFIG_DIR:-}" ]]; then
    state_file="${CLAUDE_CONFIG_DIR}/.claude.json"
  else
    state_file="$HOME/.claude.json"
  fi

  if [[ $DRY_RUN -eq 1 ]]; then
    log "$(lc "will merge hasCompletedOnboarding=true into ${state_file} so the custom API skips the account login page on first launch." "将把 hasCompletedOnboarding=true 安全合并到 ${state_file}，以便自定义 API 首次启动时跳过账户登录页。")"
    return 0
  fi

  backup_file "$state_file" || true

  if command -v python3 >/dev/null 2>&1; then
    CLAUDE_STATE_FILE="$state_file" python3 - <<'PY_STATE'
import json
import os
import pathlib
import tempfile

path = pathlib.Path(os.environ["CLAUDE_STATE_FILE"]).expanduser()
if path.exists() and path.stat().st_size:
    try:
        data = json.loads(path.read_text(encoding="utf-8"))
    except Exception as exc:
        raise SystemExit(f"existing Claude state file is not valid JSON; left unchanged / 现有 Claude 状态文件不是有效 JSON，未做修改：{path}: {exc}")
    if not isinstance(data, dict):
        raise SystemExit(f"existing Claude state file root is not a JSON object; left unchanged / 现有 Claude 状态文件根节点不是 JSON 对象，未做修改：{path}")
else:
    data = {}

data["hasCompletedOnboarding"] = True
path.parent.mkdir(parents=True, exist_ok=True)
fd, tmp = tempfile.mkstemp(prefix=".claude-state.", suffix=".json", dir=str(path.parent))
try:
    with os.fdopen(fd, "w", encoding="utf-8") as f:
        json.dump(data, f, ensure_ascii=False, indent=2)
        f.write("\n")
        f.flush()
        os.fsync(f.fileno())
    os.chmod(tmp, 0o600)
    os.replace(tmp, path)
    os.chmod(path, 0o600)
finally:
    if os.path.exists(tmp):
        os.unlink(tmp)
PY_STATE
    ok "$(lc "marked Claude Code onboarding complete: ${state_file}." "已标记 Claude Code 首次引导完成：${state_file}。")"
    return 0
  fi

  if command -v node >/dev/null 2>&1; then
    CLAUDE_STATE_FILE="$state_file" node <<'NODE_STATE'
const fs = require('fs');
const path = require('path');
const target = process.env.CLAUDE_STATE_FILE;
let data = {};
if (fs.existsSync(target) && fs.statSync(target).size > 0) {
  data = JSON.parse(fs.readFileSync(target, 'utf8'));
  if (!data || Array.isArray(data) || typeof data !== 'object') {
    throw new Error(`existing Claude state file root is not a JSON object / 现有 Claude 状态文件根节点不是 JSON 对象：${target}`);
  }
}
data.hasCompletedOnboarding = true;
fs.mkdirSync(path.dirname(target), { recursive: true });
const tmp = `${target}.tmp.${process.pid}`;
fs.writeFileSync(tmp, `${JSON.stringify(data, null, 2)}\n`, { mode: 0o600 });
fs.renameSync(tmp, target);
fs.chmodSync(target, 0o600);
NODE_STATE
    ok "$(lc "marked Claude Code onboarding complete: ${state_file}." "已标记 Claude Code 首次引导完成：${state_file}。")"
    return 0
  fi

  if [[ ! -e "$state_file" ]]; then
    umask 077
    printf '{\n  "hasCompletedOnboarding": true\n}\n' > "$state_file"
    chmod 600 "$state_file"
    ok "$(lc "created Claude Code onboarding state: ${state_file}." "已创建 Claude Code 首次引导状态：${state_file}。")"
  else
    warn "$(lc "python3/node missing; cannot safely merge ${state_file}; the account login page may still appear on first launch." "缺少 python3/node，无法安全合并 ${state_file}；首次启动时可能仍显示账户登录页。")"
  fi
}

# ---------------------------------------------------------------------------
# 主流程 / main
# ---------------------------------------------------------------------------
if [[ $SKIP_INSTALL -eq 0 ]]; then
  if [[ "$INSTALL_METHOD" == "npm" ]]; then
    install_claude_npm
  else
    install_claude_native
    ensure_local_bin_path
  fi
else
  log "$(lc 'Skipping the Claude Code install (--skip-install).' '已跳过 Claude Code 安装。')"
fi

if [[ "$CONFIG_MODE" == "shell" ]]; then
  write_shell_config
else
  write_settings_config
fi
mark_onboarding_complete

if [[ $DRY_RUN -eq 0 ]]; then
  claude_bin="$(command -v claude 2>/dev/null || true)"
  if [[ -z "$claude_bin" && -x "$HOME/.local/bin/claude" ]]; then
    claude_bin="$HOME/.local/bin/claude"
  fi
  printf '\n'
  if [[ -n "$claude_bin" ]]; then
    version_output="$($claude_bin --version 2>/dev/null || true)"
    ok "$(lc "Claude Code ready: ${version_output:-$claude_bin}" "Claude Code 已就绪：${version_output:-$claude_bin}")"
  elif [[ $SKIP_INSTALL -eq 0 ]]; then
    warn "$(lc 'install finished, but claude was not found in this shell; open a new terminal and run claude --version.' '安装已执行，但当前 shell 未找到 claude；请打开新终端后运行 claude --version。')"
  fi
  printf '%s\n' "$(lc 'Activate in the current terminal:' '立即在当前终端生效：')"
  if [[ "$CONFIG_MODE" == "shell" ]]; then
    printf '  source %q\n' "${XDG_CONFIG_HOME:-$HOME/.config}/claude-code/env"
  fi
  printf '%s\n' "$(lc 'Then enter a project and run:' '然后进入项目并运行：')"
  printf '  cd your-project-folder\n  claude\n'
else
  ok "$(lc 'Dry-run complete; nothing was modified.' 'Dry-run 完成，未修改系统。')"
fi
