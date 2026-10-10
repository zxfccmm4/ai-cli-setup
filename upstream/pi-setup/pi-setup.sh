#!/usr/bin/env bash
#
# pi-setup.sh - install or update Pi (https://pi.dev), then configure a
# provider and personalize settings, step by step.
#
# Targets Linux and macOS. For Windows use pi-setup.ps1.
#
# Remote one-liner (downloads and runs):
#   curl -fsSL https://raw.githubusercontent.com/zxfccmm4/pi-setup/main/pi-setup.sh | bash
#
# Local use:
#   ./pi-setup.sh                     # interactive wizard
#   ./pi-setup.sh -i                  # force the wizard
#   ./pi-setup.sh --base-url URL --api-key KEY --models a,b   # non-interactive
#
# Flags:
#   -i, --interactive     always run the step-by-step wizard
#   --base-url URL        endpoint base url            (env PISETUP_BASE_URL)
#   --api-key KEY         provider api key             (env PISETUP_API_KEY)
#   --models a,b,c        comma-separated model ids    (env PISETUP_MODELS)
#   --models-file FILE    read "id<TAB>name" lines as the model list
#   --lang en|zh          wizard and output language  (env PISETUP_LANG, default: en)
#   --provider NAME       provider id                  (default: derived from host)
#   --api-type TYPE       openai-completions|openai-responses|anthropic-messages
#   --default-model ID    default model to select      (default: provider/<first>)
#   --no-default          do not touch settings.json defaults
#   --dry-run             print planned changes, write nothing
#   --skip-install        never install or update, only configure
#
# Customization flags (write settings.json; see README):
#   --theme NAME          system|dark|light|light/dark|custom
#   --thinking LEVEL      off|minimal|low|medium|high|xhigh|max
#   --tools LIST          defaultTools, e.g. "+codemode" or "read,bash,+codemode"
#   --hide-thinking on|off
#   --quiet-startup on|off|header
#   --cache-warming off|streaming|idle
#   --skill-commands on|off
#   --package SOURCE      add a Pi package to settings (repeatable)
#   --set-json JSON       deep-merge arbitrary settings (repeatable)
#   --no-customize        never touch settings.json beyond provider defaults
#   -h, --help            show this help
#
# See pi-config.mjs --help for the complete flag list (auth mode, MCP servers,
# keybindings, context files, resource paths, and every settings key).
#
set -euo pipefail

RAW_BASE="${PISETUP_RAW_BASE:-https://raw.githubusercontent.com/zxfccmm4/pi-setup/main}"

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" 2>/dev/null && pwd || echo "$PWD")"

BASE_URL="${PISETUP_BASE_URL:-}"
API_KEY="${PISETUP_API_KEY:-}"
MODELS="${PISETUP_MODELS:-}"
MODELS_FILE=""
MODELS_JSON=""
LANG_CODE="${PISETUP_LANG:-en}"
PROVIDER="${PISETUP_PROVIDER:-}"
API_TYPE="${PISETUP_API_TYPE:-}"
DEFAULT_MODEL="${PISETUP_DEFAULT_MODEL:-}"
NO_DEFAULT=0
DRY_RUN=0
SKIP_INSTALL=0
FORCE_INTERACTIVE=0
CONFIG_SCRIPT=""
TMP_CONFIG=""
TMP_CONFIG_DIR=""
TMP_MODELS=""
TMP_MODELS_ERR=""
FETCH_ERROR=""

THEME=""
THINKING=""
TOOLS=""
HIDE_THINKING=""
QUIET_STARTUP=""
CACHE_WARMING=""
SKILL_COMMANDS=""
AUTH_MODE=""
ENABLED_MODELS=""
COMPACTION=""
STEERING=""
FOLLOW_UP=""
TUI_MODE=""
EDITOR_CMD=""
HTTP_PROXY=""
SESSION_DIR=""
PROJECT_TRUST=""
TELEMETRY=""
ANALYTICS=""
CACHE_MISS_NOTICES=""
COLLAPSE_CHANGELOG=""
PACKAGES=()
SET_JSONS=()
MODEL_THINKING=()
EXTENSIONS=()
SKILL_PATHS=()
PROMPT_TEMPLATES=()
THEME_FILES=()
MCP_ADDS=()
MCP_JSON=""
KEYBINDINGS=()
KEYBINDINGS_JSON=""
AGENTS_MD=""
APPEND_SYSTEM=""
SYSTEM_MD=""
NO_CUSTOMIZE=0

MODEL_IDS=()
MODEL_NAMES=()
SELECTED_IDS=()
SELECTED_NAMES=()

info() { printf '\033[1;34m==>\033[0m %s\n' "$*" >&2; }
warn() { printf '\033[1;33m!!\033[0m %s\n' "$*" >&2; }
die()  { printf '\033[1;31mxx\033[0m %s\n' "$*" >&2; exit 1; }

ECHO_SAVED=""

restore_echo() {
  if [ -n "$ECHO_SAVED" ]; then
    stty "$ECHO_SAVED" < /dev/tty 2>/dev/null || stty echo < /dev/tty 2>/dev/null || true
    ECHO_SAVED=""
  fi
}

cleanup() {
  restore_echo
  if [ -n "$TMP_CONFIG" ] && [ -f "$TMP_CONFIG" ]; then rm -f "$TMP_CONFIG"; fi
  if [ -n "$TMP_CONFIG_DIR" ] && [ -d "$TMP_CONFIG_DIR" ]; then rm -rf "$TMP_CONFIG_DIR"; fi
  if [ -n "$TMP_MODELS" ] && [ -f "$TMP_MODELS" ]; then rm -f "$TMP_MODELS"; fi
  if [ -n "$TMP_MODELS_ERR" ] && [ -f "$TMP_MODELS_ERR" ]; then rm -f "$TMP_MODELS_ERR"; fi
  return 0
}
trap cleanup EXIT

mask() {
  local s="$1" n=${#1}
  if [ "$n" -le 10 ]; then printf '********'; else printf '%s...%s' "${s:0:5}" "${s: -5}"; fi
}

have_tty() { { : </dev/tty; } 2>/dev/null; }

read_tty() {
  if have_tty; then IFS= read -r "$@" < /dev/tty; else IFS= read -r "$@"; fi
}

while [ $# -gt 0 ]; do
  case "$1" in
    -i|--interactive) FORCE_INTERACTIVE=1; shift ;;
    --skip-install) SKIP_INSTALL=1; shift ;;
    --dry-run) DRY_RUN=1; shift ;;
    --no-default) NO_DEFAULT=1; shift ;;
    --no-customize) NO_CUSTOMIZE=1; shift ;;
    -h|--help) sed -n '2,45p' "${BASH_SOURCE[0]:-$0}" | sed 's/^# \{0,1\}//'; exit 0 ;;
    --base-url) BASE_URL="$2"; shift 2 ;;
    --api-key) API_KEY="$2"; shift 2 ;;
    --models) MODELS="$2"; shift 2 ;;
    --models-file) MODELS_FILE="$2"; shift 2 ;;
    --models-json) MODELS_JSON="$2"; shift 2 ;;
    --lang) LANG_CODE="$2"; shift 2 ;;
    --provider) PROVIDER="$2"; shift 2 ;;
    --api-type) API_TYPE="$2"; shift 2 ;;
    --default-model) DEFAULT_MODEL="$2"; shift 2 ;;
    --auth-mode) AUTH_MODE="$2"; shift 2 ;;
    --theme) THEME="$2"; shift 2 ;;
    --thinking) THINKING="$2"; shift 2 ;;
    --tools) TOOLS="$2"; shift 2 ;;
    --hide-thinking) HIDE_THINKING="$2"; shift 2 ;;
    --quiet-startup) QUIET_STARTUP="$2"; shift 2 ;;
    --cache-warming) CACHE_WARMING="$2"; shift 2 ;;
    --cache-miss-notices) CACHE_MISS_NOTICES="$2"; shift 2 ;;
    --collapse-changelog) COLLAPSE_CHANGELOG="$2"; shift 2 ;;
    --skill-commands) SKILL_COMMANDS="$2"; shift 2 ;;
    --enabled-models) ENABLED_MODELS="$2"; shift 2 ;;
    --compaction) COMPACTION="$2"; shift 2 ;;
    --steering) STEERING="$2"; shift 2 ;;
    --follow-up) FOLLOW_UP="$2"; shift 2 ;;
    --tui-mode) TUI_MODE="$2"; shift 2 ;;
    --editor) EDITOR_CMD="$2"; shift 2 ;;
    --http-proxy) HTTP_PROXY="$2"; shift 2 ;;
    --session-dir) SESSION_DIR="$2"; shift 2 ;;
    --project-trust) PROJECT_TRUST="$2"; shift 2 ;;
    --telemetry) TELEMETRY="$2"; shift 2 ;;
    --analytics) ANALYTICS="$2"; shift 2 ;;
    --model-thinking) MODEL_THINKING+=("$2"); shift 2 ;;
    --package) PACKAGES+=("$2"); shift 2 ;;
    --set-json) SET_JSONS+=("$2"); shift 2 ;;
    --extension) EXTENSIONS+=("$2"); shift 2 ;;
    --skill) SKILL_PATHS+=("$2"); shift 2 ;;
    --prompt-template) PROMPT_TEMPLATES+=("$2"); shift 2 ;;
    --theme-file) THEME_FILES+=("$2"); shift 2 ;;
    --mcp-add) MCP_ADDS+=("$2"); shift 2 ;;
    --mcp-json) MCP_JSON="$2"; shift 2 ;;
    --keybinding) KEYBINDINGS+=("$2"); shift 2 ;;
    --keybindings-json) KEYBINDINGS_JSON="$2"; shift 2 ;;
    --agents-md) AGENTS_MD="$2"; shift 2 ;;
    --append-system) APPEND_SYSTEM="$2"; shift 2 ;;
    --system-md) SYSTEM_MD="$2"; shift 2 ;;
    --base-url=*) BASE_URL="${1#*=}"; shift ;;
    --api-key=*) API_KEY="${1#*=}"; shift ;;
    --models=*) MODELS="${1#*=}"; shift ;;
    --models-file=*) MODELS_FILE="${1#*=}"; shift ;;
    --models-json=*) MODELS_JSON="${1#*=}"; shift ;;
    --lang=*) LANG_CODE="${1#*=}"; shift ;;
    --provider=*) PROVIDER="${1#*=}"; shift ;;
    --api-type=*) API_TYPE="${1#*=}"; shift ;;
    --default-model=*) DEFAULT_MODEL="${1#*=}"; shift ;;
    --auth-mode=*) AUTH_MODE="${1#*=}"; shift ;;
    --theme=*) THEME="${1#*=}"; shift ;;
    --thinking=*) THINKING="${1#*=}"; shift ;;
    --tools=*) TOOLS="${1#*=}"; shift ;;
    --hide-thinking=*) HIDE_THINKING="${1#*=}"; shift ;;
    --quiet-startup=*) QUIET_STARTUP="${1#*=}"; shift ;;
    --cache-warming=*) CACHE_WARMING="${1#*=}"; shift ;;
    --cache-miss-notices=*) CACHE_MISS_NOTICES="${1#*=}"; shift ;;
    --collapse-changelog=*) COLLAPSE_CHANGELOG="${1#*=}"; shift ;;
    --skill-commands=*) SKILL_COMMANDS="${1#*=}"; shift ;;
    --enabled-models=*) ENABLED_MODELS="${1#*=}"; shift ;;
    --compaction=*) COMPACTION="${1#*=}"; shift ;;
    --steering=*) STEERING="${1#*=}"; shift ;;
    --follow-up=*) FOLLOW_UP="${1#*=}"; shift ;;
    --tui-mode=*) TUI_MODE="${1#*=}"; shift ;;
    --editor=*) EDITOR_CMD="${1#*=}"; shift ;;
    --http-proxy=*) HTTP_PROXY="${1#*=}"; shift ;;
    --session-dir=*) SESSION_DIR="${1#*=}"; shift ;;
    --project-trust=*) PROJECT_TRUST="${1#*=}"; shift ;;
    --telemetry=*) TELEMETRY="${1#*=}"; shift ;;
    --analytics=*) ANALYTICS="${1#*=}"; shift ;;
    --model-thinking=*) MODEL_THINKING+=("${1#*=}"); shift ;;
    --package=*) PACKAGES+=("${1#*=}"); shift ;;
    --set-json=*) SET_JSONS+=("${1#*=}"); shift ;;
    --extension=*) EXTENSIONS+=("${1#*=}"); shift ;;
    --skill=*) SKILL_PATHS+=("${1#*=}"); shift ;;
    --prompt-template=*) PROMPT_TEMPLATES+=("${1#*=}"); shift ;;
    --theme-file=*) THEME_FILES+=("${1#*=}"); shift ;;
    --mcp-add=*) MCP_ADDS+=("${1#*=}"); shift ;;
    --mcp-json=*) MCP_JSON="${1#*=}"; shift ;;
    --keybinding=*) KEYBINDINGS+=("${1#*=}"); shift ;;
    --keybindings-json=*) KEYBINDINGS_JSON="${1#*=}"; shift ;;
    --agents-md=*) AGENTS_MD="${1#*=}"; shift ;;
    --append-system=*) APPEND_SYSTEM="${1#*=}"; shift ;;
    --system-md=*) SYSTEM_MD="${1#*=}"; shift ;;
    *) die "unknown option: $1" ;;
  esac
done

ask() {
  local msg="$1" def="${2-}" val
  if [ -n "$def" ]; then printf '%s [%s]: ' "$msg" "$def" >&2; else printf '%s: ' "$msg" >&2; fi
  read_tty val || true
  printf '%s' "${val:-$def}"
}

ask_secret() {
  local msg="$1" val="" masked c
  if have_tty; then
    # Echo is disabled before the prompt is printed, so even an immediate
    # paste cannot reach the terminal's own echo.
    ECHO_SAVED="$(stty -g < /dev/tty 2>/dev/null || true)"
    if [ -n "$ECHO_SAVED" ]; then stty -echo < /dev/tty 2>/dev/null || true; fi
    printf '%s: ' "$msg" >&2
    while IFS= read -r -n1 c < /dev/tty; do
      case "$c" in
        $'\177'|$'\b')
          if [ -n "$val" ]; then val="${val%?}"; printf '\b \b' >&2; fi
          ;;
        ''|$'\n'|$'\r') break ;;
        *) val="$val$c"; printf '*' >&2 ;;
      esac
    done
    printf '\n' >&2
    restore_echo
    masked="$(mask "$val")"
    printf '\033[A\r\033[K%s: %s\n' "$msg" "$masked" >&2
  else
    printf '%s: ' "$msg" >&2
    IFS= read -r val || true
  fi
  printf '%s' "$val"
}

ask_yes() {
  local msg="$1" def="${2:-n}" val
  printf '%s [%s]: ' "$msg" "$def" >&2
  read_tty val || true
  val="${val:-$def}"
  case "$val" in y|Y|yes|YES|Yes) return 0 ;; *) return 1 ;; esac
}

lc() {
  if [ "$LANG_CODE" = zh ]; then printf '%s' "$2"; else printf '%s' "$1"; fi
}

join_by() { local sep="$1"; shift; local IFS="$sep"; printf '%s' "$*"; }

choose_language() {
  local v
  case "$LANG_CODE" in zh|zh-cn|zh-hans|cn) LANG_CODE=zh ;; *) LANG_CODE=en ;; esac
  printf '0) Language / 语言:  1) English  2) 简体中文\n' >&2
  v="$(ask "$(lc '   choose [1-2]' '   请选择 [1-2]')" "$([ "$LANG_CODE" = zh ] && echo 2 || echo 1)")"
  case "$v" in
    2) LANG_CODE=zh ;;
    1) LANG_CODE=en ;;
  esac
  info "$(lc 'language: English' '语言：简体中文')"
}

provider_name() {
  if [ -n "$PROVIDER" ]; then printf '%s' "$PROVIDER"; return 0; fi
  local out
  out="$(run_config --print-provider --base-url "$BASE_URL" --lang "$LANG_CODE" 2>/dev/null)" || return 1
  PROVIDER="$out"
  printf '%s' "$PROVIDER"
}

fetch_models() {
  local rc=0
  FETCH_ERROR=""
  [ -n "$BASE_URL" ] || return 1
  if [ -z "$TMP_MODELS" ]; then
    TMP_MODELS="$(mktemp "${TMPDIR:-/tmp}/pi-models.XXXXXX")"
    TMP_MODELS_ERR="${TMP_MODELS}.err"
  fi
  run_config --fetch-models --base-url "$BASE_URL" --api-key "$API_KEY" \
    --lang "$LANG_CODE" >"$TMP_MODELS" 2>"$TMP_MODELS_ERR" || rc=$?
  if [ "$rc" -ne 0 ]; then
    FETCH_ERROR="$(grep -v '^[[:space:]]*$' "$TMP_MODELS_ERR" 2>/dev/null | tail -n 1 || true)"
    warn "$(lc 'could not fetch the model list from the endpoint' '无法从该端点获取模型列表')"
    if [ -n "$FETCH_ERROR" ]; then printf '   %s\n' "$FETCH_ERROR" >&2; fi
    return 1
  fi
  MODEL_IDS=()
  MODEL_NAMES=()
  local line id name
  while IFS= read -r line; do
    [ -n "$line" ] || continue
    id="${line%%$'\t'*}"
    if [ "$id" = "$line" ]; then name="$id"; else name="${line#*$'\t'}"; fi
    MODEL_IDS+=("$id")
    MODEL_NAMES+=("$name")
  done < "$TMP_MODELS"
  [ ${#MODEL_IDS[@]} -gt 0 ]
}

VIEW_IDS=()
VIEW_NAMES=()

build_view() {
  local filter i hay
  filter="$(printf '%s' "$1" | tr '[:upper:]' '[:lower:]')"
  VIEW_IDS=()
  VIEW_NAMES=()
  for ((i = 0; i < ${#MODEL_IDS[@]}; i++)); do
    hay="$(printf '%s %s' "${MODEL_IDS[$i]}" "${MODEL_NAMES[$i]}" | tr '[:upper:]' '[:lower:]')"
    if [ -n "$filter" ]; then
      case "$hay" in *"$filter"*) : ;; *) continue ;; esac
    fi
    VIEW_IDS+=("${MODEL_IDS[$i]}")
    VIEW_NAMES+=("${MODEL_NAMES[$i]}")
  done
  [ ${#VIEW_IDS[@]} -gt 0 ]
}

print_view() {
  local max="${1:-15}" i total=${#VIEW_IDS[@]}
  for ((i = 0; i < total; i++)); do
    if [ "$((i + 1))" -le "$max" ]; then
      printf '   %d) %s\t%s\n' "$((i + 1))" "${VIEW_IDS[$i]}" "${VIEW_NAMES[$i]}" >&2
    fi
  done
  if [ "$total" -gt "$max" ]; then
    printf '   ... %s\n' "$(lc "$((total - max)) more - type text to filter, or r for the full list" "还有 $((total - max)) 个 - 输入文字过滤，或输入 r 显示全部")" >&2
  fi
  printf '%s\n' "$(lc "   ($total shown)" "   （共 $total 个）")" >&2
}

parse_selection() {
  local input="$1" token a b i
  input="${input//,/ }"
  SELECTED_IDS=()
  SELECTED_NAMES=()
  for token in $input; do
    case "$token" in
      *-*) a="${token%%-*}"; b="${token##*-}" ;;
      *) a="$token"; b="$token" ;;
    esac
    case "$a" in ''|*[!0-9]*) return 1 ;; esac
    case "$b" in ''|*[!0-9]*) return 1 ;; esac
    if [ "$a" -lt 1 ] || [ "$b" -gt ${#VIEW_IDS[@]} ] || [ "$a" -gt "$b" ]; then return 1; fi
    for ((i = a; i <= b; i++)); do
      SELECTED_IDS+=("${VIEW_IDS[$((i - 1))]}")
      SELECTED_NAMES+=("${VIEW_NAMES[$((i - 1))]}")
    done
  done
  [ ${#SELECTED_IDS[@]} -gt 0 ]
}

collect_view() {
  SELECTED_IDS=("${VIEW_IDS[@]}")
  SELECTED_NAMES=("${VIEW_NAMES[@]}")
  [ ${#SELECTED_IDS[@]} -gt 0 ]
}

pick_models() {
  local input filter="" sel
  [ ${#MODEL_IDS[@]} -gt 0 ] || return 1
  while :; do
    if ! build_view "$filter"; then
      warn "$(lc 'nothing matched that filter' '没有匹配的模型')"
      filter=""
      continue
    fi
    printf '\n%s\n' "$(lc "models from $BASE_URL:" "来自 $BASE_URL 的模型：")" >&2
    print_view 60
    input="$(ask "$(lc 'select: all / 1,3 / 2-4 / text filter (blank = all)' '请选择：all / 1,3 / 2-4 / 过滤词（留空=全部）')" '')"
    sel="${input//[0-9]/}"
    sel="${sel// /}"
    sel="${sel//,/}"
    sel="${sel//-/}"
    if [ -z "$input" ] || [ "$input" = all ] || [ "$input" = ALL ]; then
      if collect_view; then return 0; fi
    elif [ -z "$sel" ]; then
      if parse_selection "$input"; then return 0; fi
      warn "$(lc "invalid selection '$input'" "无效的选择 '$input'")"
    else
      filter="$input"
    fi
  done
}

pick_one_model() {
  local input filter="" max=15
  [ ${#MODEL_IDS[@]} -gt 0 ] || return 1
  while :; do
    if ! build_view "$filter"; then
      warn "$(lc 'nothing matched that filter' '没有匹配的模型')"
      filter=""
      continue
    fi
    printf '\n%s\n' "$(lc 'pick a model:' '选择模型：')" >&2
    print_view "$max"
    input="$(ask "$(lc 'number / text to filter / r = all / blank = skip' '编号 / 文字过滤 / r 全部 / 留空跳过')" '')"
    case "$input" in
      '') return 1 ;;
      r|R|all|ALL) max=200; continue ;;
      *[!0-9]*) filter="$input"; continue ;;
    esac
    if [ "$input" -ge 1 ] && [ "$input" -le ${#VIEW_IDS[@]} ]; then
      local prov
      prov="$(provider_name)" || return 1
      printf '%s/%s' "$prov" "${VIEW_IDS[$((input - 1))]}"
      return 0
    fi
    warn "$(lc "invalid number '$input'" "无效编号 '$input'")"
  done
}

find_pi() {
  local cand
  if cand="$(command -v pi 2>/dev/null)"; then
    if is_real_pi "$cand"; then printf '%s' "$cand"; return 0; fi
    warn "$(lc "the 'pi' on PATH is not pi.dev's Pi (${cand}); ignoring it" "PATH 上的 'pi' 不是 pi.dev 的 Pi（${cand}）；已忽略") "
  fi
  for d in "$HOME/.local/bin" "$HOME/.pi/agent/bin" "$HOME/bin" "$HOME/.bun/bin" "/usr/local/bin"; do
    if [ -x "$d/pi" ] && is_real_pi "$d/pi"; then echo "$d/pi"; return 0; fi
  done
  return 1
}

# Other tools ship a 'pi' shim (e.g. OmO/senpi's alias); pi.dev's Pi is the
# only one whose help header starts with "pi - ".
is_real_pi() {
  local head1
  head1="$("$1" --help 2>/dev/null | head -n1)" || true
  case "$head1" in
    pi\ -*) return 0 ;;
    *) return 1 ;;
  esac
}

ensure_runtime() {
  local node_dir
  if command -v node >/dev/null 2>&1; then
    node_dir="$(dirname "$(command -v node)")"
    export PATH="$node_dir:$PATH"
    return 0
  fi
  if command -v bun >/dev/null 2>&1; then
    export PATH="$HOME/.bun/bin:$PATH"
    return 0
  fi

  info "$(lc 'node.js / bun not found; installing a JavaScript runtime automatically' '未找到 node.js / bun；将自动安装 JavaScript 运行时')"

  case "$(uname -s)" in
    Darwin)
      if command -v brew >/dev/null 2>&1; then
        brew install node || die "failed to install node.js via Homebrew"
        node_dir="$(dirname "$(command -v node)")"
        export PATH="$node_dir:$PATH"
        return 0
      fi
      ;;
    Linux)
      if command -v apt-get >/dev/null 2>&1; then
        local sudo_cmd=""
        if [ "$(id -u)" -ne 0 ] && command -v sudo >/dev/null 2>&1; then
          sudo_cmd="sudo"
        fi
        $sudo_cmd apt-get update
        $sudo_cmd apt-get install -y ca-certificates curl gnupg
        if [ ! -f /etc/apt/keyrings/nodesource.gpg ] || [ ! -f /etc/apt/sources.list.d/nodesource.list ]; then
          mkdir -p /etc/apt/keyrings
          curl -fsSL https://deb.nodesource.com/gpgkey/nodesource-repo.gpg.key | gpg --dearmor -o /etc/apt/keyrings/nodesource.gpg
          echo "deb [signed-by=/etc/apt/keyrings/nodesource.gpg] https://deb.nodesource.com/node_22.x nodistro main" | $sudo_cmd tee /etc/apt/sources.list.d/nodesource.list >/dev/null
        fi
        $sudo_cmd apt-get update
        $sudo_cmd apt-get install -y nodejs
        if command -v node >/dev/null 2>&1; then
          node_dir="$(dirname "$(command -v node)")"
          export PATH="$node_dir:$PATH"
          return 0
        fi
      fi
      ;;
  esac

  if command -v curl >/dev/null 2>&1; then
    info "$(lc 'falling back to a Bun install' '回退为安装 Bun')"
    export BUN_INSTALL="$HOME/.bun"
    curl -fsSL https://bun.sh/install | bash || die "failed to install Bun"
    export PATH="$HOME/.bun/bin:$PATH"
    if command -v bun >/dev/null 2>&1; then
      return 0
    fi
  fi

  die "could not install node.js or bun automatically on this platform"
}

# The official installer is idempotent: it detects an existing pi and offers
# Reinstall / Uninstall / Cancel, so running it again is also the update path.
install_pi() {
  info "$(lc 'installing Pi (https://pi.dev)' '正在安装 Pi（https://pi.dev）')"
  if command -v curl >/dev/null 2>&1; then
    curl -fsSL https://pi.dev/install.sh | sh || die "official installer failed"
  elif command -v wget >/dev/null 2>&1; then
    wget -qO- https://pi.dev/install.sh | sh || die "official installer failed"
  elif command -v npm >/dev/null 2>&1; then
    npm install -g --ignore-scripts @earendil-works/pi-coding-agent || die "npm install failed"
  else
    die "no curl/wget/npm available to install pi"
  fi
}

# Move an existing install to the newest release of its channel. Package-manager
# installs (npm / bun) update through `pi update`, which no-ops when already
# current; a managed install updates through the same command. Failures warn
# and continue, so the config step still runs.
update_pi() {
  local bin="$1"
  if [ "$DRY_RUN" -eq 1 ]; then
    info "$(lc 'would check for a newer Pi release (pi update)' '将检查 Pi 新版本（pi update）')"
    return 0
  fi
  info "$(lc 'checking for a newer Pi release' '正在检查 Pi 新版本')"
  if ! "$bin" update; then
    warn "$(lc "'pi update' failed; continuing with the installed version" "'pi update' 失败；继续使用已安装版本")"
  fi
}

ensure_config_script() {
  local local_path="$SCRIPT_DIR/pi-config.mjs"
  if [ -f "$local_path" ]; then CONFIG_SCRIPT="$local_path"; return; fi
  # BSD mktemp (macOS) only substitutes X's at the END of a template, so
  # "pi-config.XXXXXX.mjs" would become a literal filename that collides on
  # the second run. Create a temp directory instead and put the helper inside
  # it with the .mjs extension node needs for ESM.
  local tmpdir tmp
  tmpdir="$(mktemp -d "${TMPDIR:-/tmp}/pi-config.XXXXXX")" || die "cannot create a temp directory under ${TMPDIR:-/tmp}"
  tmp="$tmpdir/pi-config.mjs"
  info "downloading pi-config.mjs" >&2
  # raw.githubusercontent.com is the canonical source; jsDelivr mirrors the
  # same repo and stays reachable where raw is blocked (e.g. CN-region VMs).
  local url ok=0
  for url in "$RAW_BASE/pi-config.mjs" \
             "https://cdn.jsdelivr.net/gh/zxfccmm4/pi-setup@main/pi-config.mjs"; do
    if command -v curl >/dev/null 2>&1; then
      curl -fsSL --connect-timeout 10 --max-time 120 "$url" -o "$tmp" && ok=1
    elif command -v wget >/dev/null 2>&1; then
      wget -q --timeout=120 -O "$tmp" "$url" && ok=1
    else
      die "need curl or wget to download pi-config.mjs"
    fi
    if [ "$ok" -eq 1 ] && [ -s "$tmp" ]; then break; fi
    ok=0
  done
  if [ "$ok" -ne 1 ] || [ ! -s "$tmp" ]; then
    rm -rf "$tmpdir"
    die "failed to download pi-config.mjs (tried raw.githubusercontent.com and cdn.jsdelivr.net)"
  fi
  TMP_CONFIG_DIR="$tmpdir"
  TMP_CONFIG="$tmp"
  CONFIG_SCRIPT="$tmp"
}

run_config() {
  ensure_runtime
  ensure_config_script
  if command -v node >/dev/null 2>&1; then
    node "$CONFIG_SCRIPT" "$@"
  elif command -v bun >/dev/null 2>&1; then
    bun "$CONFIG_SCRIPT" "$@"
  else
    die "need node or bun to write pi config"
  fi
}

summarize_ids() {
  local max=6 joined="" i total=$#
  local -a ids=("$@")
  for ((i = 0; i < total; i++)); do
    if [ "$((i + 1))" -le "$max" ]; then
      if [ -n "$joined" ]; then joined="$joined,${ids[$i]}"; else joined="${ids[$i]}"; fi
    fi
  done
  if [ "$total" -gt "$max" ]; then
    joined="$joined,$(lc "+$((total - max)) more" "等共 $total 个")"
  fi
  printf '%s' "$joined"
}

customize_wizard() {
  local v
  printf '\n' >&2
  info "$(lc 'personalize Pi (blank = keep current / skip)' '个性化 Pi 配置（留空 = 保持现状 / 跳过）')"
  printf '\n' >&2

  printf '%s\n' "$(lc 'a) Theme: 1) system  2) dark  3) light  4) light/dark (auto)  (blank = skip)' 'a) 主题：1) system  2) dark  3) light  4) light/dark（自动） （留空=跳过）')" >&2
  v="$(ask "$(lc '   choose [1-4]' '   请选择 [1-4]')" '')"
  case "$v" in
    1) THEME=system ;;
    2) THEME=dark ;;
    3) THEME=light ;;
    4) THEME=light/dark ;;
    '') : ;;
    *) THEME="$v" ;;
  esac

  printf '%s\n' "$(lc 'b) Thinking level: 1) off  2) minimal  3) low  4) medium  5) high  6) xhigh  7) max  (blank = skip)' 'b) 推理档位：1) off  2) minimal  3) low  4) medium  5) high  6) xhigh  7) max （留空=跳过）')" >&2
  v="$(ask "$(lc '   choose [1-7]' '   请选择 [1-7]')" '')"
  case "$v" in
    1) THINKING=off ;;
    2) THINKING=minimal ;;
    3) THINKING=low ;;
    4) THINKING=medium ;;
    5) THINKING=high ;;
    6) THINKING=xhigh ;;
    7) THINKING=max ;;
    '') : ;;
    *) THINKING="$v" ;;
  esac

  printf '%s\n' "$(lc 'c) Tools: 1) keep defaults  2) defaults + codemode  3) defaults + codemode + tool_search  4) type a list' 'c) 工具：1) 保持默认  2) 默认 + codemode  3) 默认 + codemode + tool_search  4) 手动输入列表')" >&2
  v="$(ask "$(lc '   choose [1-4]' '   请选择 [1-4]')" '')"
  case "$v" in
    1) TOOLS="__keep__" ;;
    2) TOOLS="+codemode" ;;
    3) TOOLS="+codemode,+tool_search" ;;
    4) TOOLS="$(ask "$(lc '   list (e.g. read,bash,+codemode)' '   列表（例：read,bash,+codemode）')" '')" ;;
    '') : ;;
    *) TOOLS="$v" ;;
  esac

  v="$(ask "$(lc 'd) Hide thinking blocks? [y/N] (blank = skip)' 'd) 隐藏思考块？[y/N]（留空=跳过）')" '')"
  case "$v" in y|Y|yes|YES) HIDE_THINKING=on ;; n|N|no|NO) HIDE_THINKING=off ;; *) : ;; esac

  printf '%s\n' "$(lc 'e) Quiet startup: 1) on  2) off  3) header only  (blank = skip)' 'e) 安静启动：1) 开启  2) 关闭  3) 仅保留头部（留空=跳过）')" >&2
  v="$(ask "$(lc '   choose [1-3]' '   请选择 [1-3]')" '')"
  case "$v" in
    1) QUIET_STARTUP=on ;;
    2) QUIET_STARTUP=off ;;
    3) QUIET_STARTUP=header ;;
    '') : ;;
    *) QUIET_STARTUP="$v" ;;
  esac

  printf '%s\n' "$(lc 'f) Cache warming: 1) streaming  2) idle  3) off  (blank = skip)' 'f) 缓存预热：1) streaming  2) idle  3) off （留空=跳过）')" >&2
  v="$(ask "$(lc '   choose [1-3]' '   请选择 [1-3]')" '')"
  case "$v" in
    1) CACHE_WARMING=streaming ;;
    2) CACHE_WARMING=idle ;;
    3) CACHE_WARMING=off ;;
    '') : ;;
    *) CACHE_WARMING="$v" ;;
  esac

  printf '%s\n' "$(lc 'g) Install a Pi package (e.g. npm:@foo/pi-tools or git:github.com/user/repo), blank = skip' 'g) 安装 Pi 包（例：npm:@foo/pi-tools 或 git:github.com/user/repo），留空=跳过')" >&2
  v="$(ask "$(lc '   package source' '   包来源')" '')"
  while [ -n "$v" ]; do
    PACKAGES+=("$v")
    v="$(ask "$(lc '   another package (blank = done)' '   另一个包（留空=完成）')" '')"
  done

  printf '%s\n' "$(lc 'h) Add an MCP server (stdio or HTTP), blank = skip' 'h) 添加 MCP 服务器（stdio 或 HTTP），留空=跳过')" >&2
  v="$(ask "$(lc '   server name' '   服务器名称')" '')"
  while [ -n "$v" ]; do
    local cmd
    cmd="$(ask "$(lc '   command (stdio, e.g. npx) or url (http)' '   命令（stdio，如 npx）或 url（http）')" '')"
    if [ -n "$cmd" ]; then
      case "$cmd" in
        http://*|https://*)
          MCP_ADDS+=("$v={\"url\":\"$cmd\"}")
          ;;
        *)
          local args
          args="$(ask "$(lc '   arguments, space-separated (blank = none)' '   参数，空格分隔（留空=无）')" '')"
          local json_args="[]"
          if [ -n "$args" ]; then
            json_args="$(printf '%s' "$args" | tr ' ' '\n' | sed 's/\\/\\\\/g; s/"/\\"/g' | sed 's/.*/"&"/' | paste -sd, -)"
            json_args="[$json_args]"
          fi
          MCP_ADDS+=("$v={\"command\":\"$cmd\",\"args\":$json_args}")
          ;;
      esac
    fi
    v="$(ask "$(lc '   another server (blank = done)' '   另一个服务器（留空=完成）')" '')"
  done

  printf '%s\n' "$(lc 'i) Add persistent instructions for every project? (AGENTS.md), blank = skip' 'i) 添加适用于所有项目的持久指令？（AGENTS.md），留空=跳过')" >&2
  v="$(ask "$(lc '   instructions' '   指令内容')" '')"
  [ -n "$v" ] && AGENTS_MD="$v"
}

# Offer to keep the credential in auth.json (chmod 600) instead of models.json.
ask_auth_mode() {
  local v
  printf '%s\n' "$(lc 'Where should the API key be stored?  1) models.json (default, simple)  2) auth.json (credential file, chmod 600)' 'API key 存在哪里？1) models.json（默认，简单）  2) auth.json（凭据文件，权限 600）')" >&2
  v="$(ask "$(lc '   choose [1-2]' '   请选择 [1-2]')" '1')"
  case "$v" in
    2) AUTH_MODE=auth ;;
    *) AUTH_MODE=models ;;
  esac
}

wizard() {
  printf '\n' >&2
  choose_language
  ensure_runtime
  printf '\n' >&2
  info "$(lc 'step-by-step setup (press Enter to accept the [default])' '逐步配置（直接回车 = 采用 [默认值]）')"
  printf '\n' >&2

  local v
  v="$(ask "$(lc '1) Endpoint base URL (e.g. https://api.example.com/v1)' '1) 接口 base URL（例：https://api.example.com/v1）')" "$BASE_URL")"
  [ -n "$v" ] || die "$(lc 'base URL is required' 'base URL 必填')"
  BASE_URL="$v"

  v="$(ask_secret "$(lc '2) API key' '2) API key')")"
  [ -n "$v" ] && API_KEY="$v"
  [ -n "$API_KEY" ] || die "$(lc 'API key is required' 'API key 必填')"

  if [ -z "$MODELS" ] && [ -z "$MODELS_FILE" ] && [ ${#SELECTED_IDS[@]} -eq 0 ]; then
    info "$(lc 'fetching the model list from the endpoint...' '正在从端点获取模型列表...')"
    if fetch_models; then
      info "$(lc "found ${#MODEL_IDS[@]} models" "共发现 ${#MODEL_IDS[@]} 个模型")"
      if pick_models; then
        MODELS="$(join_by , "${SELECTED_IDS[@]}")"
      fi
    else
      warn "$(lc 'falling back to typing model ids by hand' '改用手动输入模型 id')"
    fi
  fi

  if [ -z "$MODELS" ] && [ -z "$MODELS_FILE" ]; then
    v="$(ask "$(lc '3) Model ids, comma-separated (e.g. gpt-4o,gpt-4o-mini)' '3) 模型 id，逗号分隔（例：gpt-4o,gpt-4o-mini）')" "$MODELS")"
    [ -n "$v" ] || die "$(lc 'at least one model is required' '至少需要一个模型')"
    MODELS="$v"
  fi

  v="$(ask "$(lc '4) Provider name (blank = auto from host)' '4) Provider 名称（留空 = 由域名自动推导）')" "$PROVIDER")"
  PROVIDER="$v"
  if [ -z "$PROVIDER" ]; then provider_name >/dev/null 2>&1 || true; fi

  printf '%s\n' "$(lc '5) API protocol:  1) openai-completions (default)  2) openai-responses  3) anthropic-messages' '5) API 协议：1) openai-completions（默认） 2) openai-responses  3) anthropic-messages')" >&2
  v="$(ask "$(lc '   choose [1-3]' '   请选择 [1-3]')" '1')"
  case "$v" in
    1) API_TYPE="openai-completions" ;;
    2) API_TYPE="openai-responses" ;;
    3) API_TYPE="anthropic-messages" ;;
    *) warn "$(lc "unknown choice '$v', using openai-completions" "未知选项 '$v'，改用 openai-completions")"; API_TYPE="openai-completions" ;;
  esac

  ask_auth_mode

  v="$(ask "$(lc '6) Default model (blank = provider/<first model>)' '6) 默认模型（留空 = provider/<第一个模型>）')" "$DEFAULT_MODEL")"
  DEFAULT_MODEL="$v"

  printf '\n' >&2
  info "$(lc 'about to write:' '即将写入：')"
  printf '   %s : %s\n' "$(lc 'Base URL' 'Base URL')" "$BASE_URL" >&2
  printf '   %s : %s\n' "$(lc 'API key ' 'API key ')" "$(mask "$API_KEY")" >&2
  printf '   %s : %s\n' "$(lc 'Models  ' '模型    ')" "$(summarize_ids ${MODELS//,/ })" >&2
  printf '   %s : %s\n' "$(lc 'Provider' 'Provider')" "${PROVIDER:-(auto)}" >&2
  printf '   %s : %s\n' "$(lc 'Protocol' '协议    ')" "$API_TYPE" >&2
  printf '   %s : %s\n' "$(lc 'Key store' '密钥存放')" "$AUTH_MODE" >&2
  if [ "$NO_DEFAULT" -eq 0 ]; then
    printf '   %s : %s\n' "$(lc 'Default ' '默认模型')" "${DEFAULT_MODEL:-(provider/<first model>)}" >&2
  fi
  printf '\n' >&2
  if ! ask_yes "$(lc '7) Write this config?' '7) 写入以上配置？')" "n"; then info "$(lc 'cancelled' '已取消')"; exit 0; fi

  if [ "$NO_CUSTOMIZE" -eq 0 ]; then
    printf '\n' >&2
    if ask_yes "$(lc '8) Personalize settings now (theme / thinking / tools / packages)?' '8) 现在个性化设置（主题 / 推理档位 / 工具 / 包）？')" "n"; then
      customize_wizard
    fi
  fi
}

PI_BIN_FOUND=""

if [ "$SKIP_INSTALL" -eq 0 ]; then
  if PI_BIN="$(find_pi)"; then
    PI_BIN_FOUND="$PI_BIN"
    info "pi already installed: $("$PI_BIN" --version 2>/dev/null || echo "$PI_BIN") - checking for updates"
    update_pi "$PI_BIN"
  else
    if have_tty; then
      if ask_yes "$(lc 'Pi is not installed. Install it now?' 'Pi 尚未安装，现在安装？')" "y"; then
        install_pi
      else
        die "$(lc 'pi is required; aborting' 'pi 是必需的；已中止')"
      fi
    else
      install_pi
    fi
    PI_BIN="$(find_pi)" || die "$(lc 'pi was installed but no pi binary was found; check the installer output above' 'pi 已安装但未找到 pi 可执行文件；请查看上方安装器输出')"
    PI_BIN_FOUND="$PI_BIN"
    info "installed: $("$PI_BIN" --version 2>/dev/null || echo "$PI_BIN")"
  fi
else
  PI_BIN="$(find_pi 2>/dev/null)" || true
  PI_BIN_FOUND="$PI_BIN"
  info "$(lc '--skip-install set, not checking installation' '已指定 --skip-install，跳过安装检查')"
fi
HAVE_CUSTOMIZE_FLAGS=0
if [ -n "$THEME" ] || [ -n "$THINKING" ] || [ -n "$TOOLS" ] || [ -n "$HIDE_THINKING" ] || \
   [ -n "$QUIET_STARTUP" ] || [ -n "$CACHE_WARMING" ] || [ -n "$SKILL_COMMANDS" ] || \
   [ -n "$CACHE_MISS_NOTICES" ] || [ -n "$COLLAPSE_CHANGELOG" ] || [ -n "$ENABLED_MODELS" ] || \
   [ -n "$COMPACTION" ] || [ -n "$STEERING" ] || [ -n "$FOLLOW_UP" ] || [ -n "$TUI_MODE" ] || \
   [ -n "$EDITOR_CMD" ] || [ -n "$HTTP_PROXY" ] || [ -n "$SESSION_DIR" ] || \
   [ -n "$PROJECT_TRUST" ] || [ -n "$TELEMETRY" ] || [ -n "$ANALYTICS" ] || \
   [ -n "$AGENTS_MD" ] || [ -n "$APPEND_SYSTEM" ] || [ -n "$SYSTEM_MD" ] || [ -n "$MCP_JSON" ] || \
   [ -n "$KEYBINDINGS_JSON" ] || \
   [ ${#PACKAGES[@]} -gt 0 ] || [ ${#SET_JSONS[@]} -gt 0 ] || [ ${#MODEL_THINKING[@]} -gt 0 ] || \
   [ ${#EXTENSIONS[@]} -gt 0 ] || [ ${#SKILL_PATHS[@]} -gt 0 ] || [ ${#PROMPT_TEMPLATES[@]} -gt 0 ] || \
   [ ${#THEME_FILES[@]} -gt 0 ] || [ ${#MCP_ADDS[@]} -gt 0 ] || [ ${#KEYBINDINGS[@]} -gt 0 ]; then
  HAVE_CUSTOMIZE_FLAGS=1
fi

if [ "$FORCE_INTERACTIVE" -eq 1 ]; then
  wizard
elif [ -n "$BASE_URL" ] || [ -n "$API_KEY" ] || [ -n "$MODELS" ] || [ -n "$MODELS_FILE" ] || [ -n "$MODELS_JSON" ]; then
  if [ -z "$MODELS" ] && [ -z "$MODELS_FILE" ] && [ -z "$MODELS_JSON" ]; then wizard; fi
  if [ -z "$BASE_URL" ] || [ -z "$API_KEY" ]; then wizard; fi
elif [ "$HAVE_CUSTOMIZE_FLAGS" -eq 0 ]; then
  wizard
fi

CONFIG_ARGS=()
if [ -n "$BASE_URL" ] || [ -n "$API_KEY" ] || [ -n "$MODELS" ] || [ -n "$MODELS_FILE" ] || [ -n "$MODELS_JSON" ]; then
  CONFIG_ARGS+=(--base-url "$BASE_URL" --api-key "$API_KEY")
  if [ -n "$MODELS_JSON" ]; then
    CONFIG_ARGS+=(--models-json "$MODELS_JSON")
  elif [ -n "$MODELS_FILE" ]; then
    CONFIG_ARGS+=(--models-file "$MODELS_FILE")
  else
    CONFIG_ARGS+=(--models "$MODELS")
  fi
fi
CONFIG_ARGS+=(--lang "$LANG_CODE")
if [ -n "$PROVIDER" ]; then CONFIG_ARGS+=(--provider "$PROVIDER"); fi
if [ -n "$API_TYPE" ]; then CONFIG_ARGS+=(--api-type "$API_TYPE"); fi
if [ -n "$DEFAULT_MODEL" ]; then CONFIG_ARGS+=(--default-model "$DEFAULT_MODEL"); fi
if [ -n "$AUTH_MODE" ]; then CONFIG_ARGS+=(--auth-mode "$AUTH_MODE"); fi
if [ "$NO_DEFAULT" -eq 1 ]; then CONFIG_ARGS+=(--no-default); fi
if [ "$DRY_RUN" -eq 1 ]; then CONFIG_ARGS+=(--dry-run); fi

if [ "$NO_CUSTOMIZE" -eq 0 ]; then
  if [ -n "$THEME" ] && [ "$THEME" != "__keep__" ]; then CONFIG_ARGS+=(--theme "$THEME"); fi
  if [ -n "$THINKING" ]; then CONFIG_ARGS+=(--thinking "$THINKING"); fi
  if [ -n "$TOOLS" ] && [ "$TOOLS" != "__keep__" ]; then CONFIG_ARGS+=(--tools "$TOOLS"); fi
  if [ -n "$HIDE_THINKING" ]; then CONFIG_ARGS+=(--hide-thinking "$HIDE_THINKING"); fi
  if [ -n "$QUIET_STARTUP" ]; then CONFIG_ARGS+=(--quiet-startup "$QUIET_STARTUP"); fi
  if [ -n "$CACHE_WARMING" ]; then CONFIG_ARGS+=(--cache-warming "$CACHE_WARMING"); fi
  if [ -n "$CACHE_MISS_NOTICES" ]; then CONFIG_ARGS+=(--cache-miss-notices "$CACHE_MISS_NOTICES"); fi
  if [ -n "$COLLAPSE_CHANGELOG" ]; then CONFIG_ARGS+=(--collapse-changelog "$COLLAPSE_CHANGELOG"); fi
  if [ -n "$SKILL_COMMANDS" ]; then CONFIG_ARGS+=(--skill-commands "$SKILL_COMMANDS"); fi
  if [ -n "$ENABLED_MODELS" ]; then CONFIG_ARGS+=(--enabled-models "$ENABLED_MODELS"); fi
  if [ -n "$COMPACTION" ]; then CONFIG_ARGS+=(--compaction "$COMPACTION"); fi
  if [ -n "$STEERING" ]; then CONFIG_ARGS+=(--steering "$STEERING"); fi
  if [ -n "$FOLLOW_UP" ]; then CONFIG_ARGS+=(--follow-up "$FOLLOW_UP"); fi
  if [ -n "$TUI_MODE" ]; then CONFIG_ARGS+=(--tui-mode "$TUI_MODE"); fi
  if [ -n "$EDITOR_CMD" ]; then CONFIG_ARGS+=(--editor "$EDITOR_CMD"); fi
  if [ -n "$HTTP_PROXY" ]; then CONFIG_ARGS+=(--http-proxy "$HTTP_PROXY"); fi
  if [ -n "$SESSION_DIR" ]; then CONFIG_ARGS+=(--session-dir "$SESSION_DIR"); fi
  if [ -n "$PROJECT_TRUST" ]; then CONFIG_ARGS+=(--project-trust "$PROJECT_TRUST"); fi
  if [ -n "$TELEMETRY" ]; then CONFIG_ARGS+=(--telemetry "$TELEMETRY"); fi
  if [ -n "$ANALYTICS" ]; then CONFIG_ARGS+=(--analytics "$ANALYTICS"); fi
  if [ -n "$MCP_JSON" ]; then CONFIG_ARGS+=(--mcp-json "$MCP_JSON"); fi
  if [ -n "$KEYBINDINGS_JSON" ]; then CONFIG_ARGS+=(--keybindings-json "$KEYBINDINGS_JSON"); fi
  if [ -n "$AGENTS_MD" ]; then CONFIG_ARGS+=(--agents-md "$AGENTS_MD"); fi
  if [ -n "$APPEND_SYSTEM" ]; then CONFIG_ARGS+=(--append-system "$APPEND_SYSTEM"); fi
  if [ -n "$SYSTEM_MD" ]; then CONFIG_ARGS+=(--system-md "$SYSTEM_MD"); fi
  for item in "${PACKAGES[@]+"${PACKAGES[@]}"}"; do CONFIG_ARGS+=(--package "$item"); done
  for item in "${SET_JSONS[@]+"${SET_JSONS[@]}"}"; do CONFIG_ARGS+=(--set-json "$item"); done
  for item in "${MODEL_THINKING[@]+"${MODEL_THINKING[@]}"}"; do CONFIG_ARGS+=(--model-thinking "$item"); done
  for item in "${EXTENSIONS[@]+"${EXTENSIONS[@]}"}"; do CONFIG_ARGS+=(--extension "$item"); done
  for item in "${SKILL_PATHS[@]+"${SKILL_PATHS[@]}"}"; do CONFIG_ARGS+=(--skill "$item"); done
  for item in "${PROMPT_TEMPLATES[@]+"${PROMPT_TEMPLATES[@]}"}"; do CONFIG_ARGS+=(--prompt-template "$item"); done
  for item in "${THEME_FILES[@]+"${THEME_FILES[@]}"}"; do CONFIG_ARGS+=(--theme-file "$item"); done
  for item in "${MCP_ADDS[@]+"${MCP_ADDS[@]}"}"; do CONFIG_ARGS+=(--mcp-add "$item"); done
  for item in "${KEYBINDINGS[@]+"${KEYBINDINGS[@]}"}"; do CONFIG_ARGS+=(--keybinding "$item"); done
fi

# The official installer prefers ~/.local/bin, but only when that directory is
# already on PATH; on a fresh root account it falls back to
# <agent-dir>/bin (e.g. /root/.pi/agent/bin), which shells do not search.
# Report that instead of printing a bare `pi` the user cannot run.
pi_on_path() {
  local p
  p="$(command -v pi 2>/dev/null)" || return 1
  [ -n "$p" ] || return 1
  is_real_pi "$p"
}

shell_profile_file() {
  case "$(basename "${SHELL:-sh}")" in
    fish) printf '%s/.config/fish/config.fish' "$HOME" ;;
    zsh) printf '%s/.zshrc' "${ZDOTDIR:-$HOME}" ;;
    bash)
      if [ -f "$HOME/.bashrc" ]; then printf '%s/.bashrc' "$HOME"; else printf '%s/.profile' "$HOME"; fi
      ;;
    *) printf '%s/.profile' "$HOME" ;;
  esac
}

path_export_line() {
  local dir="$1"
  case "$(basename "${SHELL:-sh}")" in
    fish) printf 'fish_add_path %s' "$dir" ;;
    *) printf 'export PATH="%s:$PATH"' "$dir" ;;
  esac
}

path_contains_dir() {
  case ":${PATH:-}:" in
    *":$1:"*) return 0 ;;
    *) return 1 ;;
  esac
}

report_pi_path() {
  local bin_dir profile line
  if pi_on_path; then
    info "$(lc 'done. Start Pi with:' '完成。用以下命令启动 Pi：')"
    printf '   cd /path/to/project && pi\n' >&2
    printf '   %s\n' "$(lc 'authenticate a built-in provider with /login inside Pi' '在 Pi 内用 /login 登录内置 provider')" >&2
    return 0
  fi

  if [ -z "$PI_BIN_FOUND" ]; then
    warn "$(lc 'no pi binary was found; install Pi and re-run this script' '未找到 pi 可执行文件；请安装 Pi 后重新运行本脚本')"
    return 1
  fi

  bin_dir="$(dirname "$PI_BIN_FOUND")"
  profile="$(shell_profile_file)"
  line="$(path_export_line "$bin_dir")"

  printf '\n' >&2
  if path_contains_dir "$bin_dir"; then
    # The directory is already searched; something else named pi wins the lookup.
    warn "$(lc "'pi' currently resolves to a different program; use the full path below" "'pi' 当前解析到其它程序；请用下面的完整路径")"
    printf '   %s %s\n' "$(lc 'resolves to' '当前解析为')" "$(command -v pi 2>/dev/null)" >&2
  else
    warn "$(lc 'Pi is installed, but its directory is not on your PATH yet' 'Pi 已安装，但其目录还不在 PATH 中')"
  fi
  printf '   %s %s\n' "$(lc 'binary' '可执行文件')" "$PI_BIN_FOUND" >&2
  printf '   %s %s\n' "$(lc 'version' '版本    ')" "$("$PI_BIN_FOUND" --version 2>/dev/null || echo '?')" >&2
  printf '\n' >&2
  printf '%s\n' "$(lc 'Run it now with:' '现在可以这样运行：')" >&2
  printf '   %s\n' "$PI_BIN_FOUND" >&2
  printf '\n' >&2
  printf '%s\n' "$(lc 'To use the short pi command, add it to PATH:' '想直接用 pi 命令，把它加入 PATH：')" >&2
  printf '   %s\n' "$line" >&2
  printf '\n' >&2
  if path_contains_dir "$bin_dir"; then
    printf '   %s\n' "$(lc 'already on PATH - check for a conflicting pi earlier in PATH' '已在 PATH 中 - 请检查 PATH 靠前位置是否有冲突的 pi')" >&2
  elif [ -n "$line" ] && [ -n "$profile" ] && ! grep -Fxq "$line" "$profile" 2>/dev/null; then
    if have_tty && ask_yes "$(lc "Append that line to ${profile} now?" "现在就把它追加到 ${profile}？")" "y"; then
      mkdir -p "${profile%/*}" 2>/dev/null || true
      if printf '\n# Pi\n%s\n' "$line" >> "$profile" 2>/dev/null; then
        info "$(lc "updated ${profile} - restart your shell or run: ${line}" "已更新 ${profile} - 重启 shell 或运行：${line}")"
      else
        warn "$(lc "could not write ${profile}; add the line above by hand" "无法写入 ${profile}；请手动添加上面的行")"
      fi
    fi
  fi
  printf '   %s\n' "$(lc 'authenticate a built-in provider with /login inside Pi' '在 Pi 内用 /login 登录内置 provider')" >&2
}

info "$(lc 'writing config' '正在写入配置')"
run_config "${CONFIG_ARGS[@]}"

report_pi_path
