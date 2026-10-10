#!/usr/bin/env bash
#
# changelog.sh — 从 git 历史生成 Keep a Changelog 风格的 CHANGELOG。
# changelog.sh — generate a Keep a Changelog file from git history.
#
# 只依赖 git + awk + sed + coreutils，无第三方包。bash 3.2 兼容。
# Requires only git/awk/sed/coreutils. bash 3.2 compatible.
#
# 用法 / usage:
#   scripts/changelog.sh                             # [Unreleased] 到 stdout
#   scripts/changelog.sh v1.0.0 HEAD                 # 指定区间
#   scripts/changelog.sh --version v1.1.0            # 带版本号（日期默认今天）
#   scripts/changelog.sh --version v1.1.0 --update CHANGELOG.md
#   scripts/changelog.sh --all --update CHANGELOG.md # 按 tag 重建整份文件
#
# 选项 / options:
#   --version V        节标题用 `## [V] - DATE`（默认 `## [Unreleased]`）
#   --date D           日期（默认今天，YYYY-MM-DD）
#   --update FILE      幂等写入/替换 FILE 中的对应节
#   --all              按所有 v* tag 重建整份 CHANGELOG
#   --repo OWNER/REPO  提交链接用的仓库（默认从 origin 推导）
#   --no-links         不生成提交链接
#   -h, --help
#
set -euo pipefail

PROG="$(basename "$0")"
VERSION=""
DATE="$(date +%Y-%m-%d)"
UPDATE_FILE=""
ALL=0
NO_LINKS=0
REPO_SLUG="${CHANGELOG_REPO:-}"
FROM=""
TO="HEAD"

SEP=$'\037'   # 0x1f unit separator，用于分隔 log 字段

# ---------------------------------------------------------------------------
# 参数
# ---------------------------------------------------------------------------
usage() {
  sed -n '3,24p' "$0" | sed 's/^# \{0,1\}//'
}

while [ $# -gt 0 ]; do
  case "$1" in
    --version)  [ $# -ge 2 ] || { echo "$PROG: --version needs a value" >&2; exit 2; }; VERSION="$2"; shift 2 ;;
    --date)     [ $# -ge 2 ] || { echo "$PROG: --date needs a value" >&2; exit 2; }; DATE="$2"; shift 2 ;;
    --update)   [ $# -ge 2 ] || { echo "$PROG: --update needs a value" >&2; exit 2; }; UPDATE_FILE="$2"; shift 2 ;;
    --repo)     [ $# -ge 2 ] || { echo "$PROG: --repo needs a value" >&2; exit 2; }; REPO_SLUG="$2"; shift 2 ;;
    --all)      ALL=1; shift ;;
    --no-links) NO_LINKS=1; shift ;;
    -h|--help)  usage; exit 0 ;;
    -*)         echo "$PROG: unknown option: $1" >&2; exit 2 ;;
    *)
      if [ -z "$FROM" ]; then FROM="$1"
      elif [ "$TO" = "HEAD" ]; then TO="$1"
      fi
      shift
      ;;
  esac
done

command -v git >/dev/null 2>&1 || { echo "$PROG: git not found" >&2; exit 1; }
git rev-parse --git-dir >/dev/null 2>&1 || { echo "$PROG: not a git repository" >&2; exit 1; }

# ---------------------------------------------------------------------------
# 仓库 slug（提交链接用）
# ---------------------------------------------------------------------------
if [ -z "$REPO_SLUG" ] && [ "$NO_LINKS" -eq 0 ]; then
  remote="$(git config --get remote.origin.url 2>/dev/null || true)"
  REPO_SLUG="${remote%.git}"
  case "$REPO_SLUG" in
    *github.com/*) REPO_SLUG="${REPO_SLUG##*github.com/}" ;;
    *github.com:*) REPO_SLUG="${REPO_SLUG##*github.com:}" ;;
    *) REPO_SLUG=""; NO_LINKS=1 ;;
  esac
fi

HEADER_ZH='本项目所有值得注意的改动都记录在此文件。
格式参考 [Keep a Changelog](https://keepachangelog.com/zh-CN/1.1.0/)，版本号遵循 [语义化版本](https://semver.org/lang/zh-CN/)。

All notable changes to this project are documented here.
Format based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/), versioning follows [Semantic Versioning](https://semver.org/).'

# ---------------------------------------------------------------------------
# 一次 awk 扫描，按约定式提交类型分桶输出
# render_body <range>
# ---------------------------------------------------------------------------
render_body() {
  local range="$1"
  git log --no-merges --format="%H${SEP}%h${SEP}%s" "$range" 2>/dev/null | awk \
    -v sep="$SEP" -v links="$NO_LINKS" -v slug="$REPO_SLUG" '
    BEGIN {
      n = split("feat fix perf refactor docs test ci build chore other", order, " ")
      title["feat"]     = "✨ Features"
      title["fix"]      = "🐛 Bug Fixes"
      title["perf"]     = "⚡ Performance"
      title["refactor"] = "♻️ Refactoring"
      title["docs"]     = "📝 Documentation"
      title["test"]     = "✅ Tests"
      title["ci"]       = "🔧 CI"
      title["build"]    = "📦 Build"
      title["chore"]    = "🔨 Chores"
      title["other"]    = "📌 Other"
      skip = "^(chore\\(release\\)|docs\\(changelog\\)|chore: release)"
    }

    function clean(s) {
      if (s ~ /^[A-Za-z]+(\([^)]*\))?!?: /) sub(/^[A-Za-z]+(\([^)]*\))?!?: /, "", s)
      else if (s ~ /^[^:]+: /)              sub(/^[^:]+: /, "", s)
      gsub(/^[[:space:]]+/, "", s)
      gsub(/[[:space:]]+$/, "", s)
      return s
    }

    function kind(s,   t) {
      if (s !~ /^[A-Za-z]+(\([^)]*\))?!?:/) return "other"
      t = s
      sub(/[(!:].*$/, "", t)
      t = tolower(t)
      if (t == "feat" || t == "fix" || t == "perf" || t == "refactor" || \
          t == "docs" || t == "test" || t == "ci" || t == "build" || t == "chore") return t
      return "other"
    }

    function line_for(short, text) {
      if (links == "1") return "- " text " (`" short "`)"
      return "- " text " ([`" short "`](https://github.com/" slug "/commit/" full "))"
    }

    {
      full = $0; sub(sep ".*", "", full)
      rest = $0; sub("^[^" sep "]*" sep, "", rest)
      short = rest; sub(sep ".*", "", short)
      subject = rest; sub("^[^" sep "]*" sep, "", subject)

      if (subject == "" || subject ~ skip) next

      k = kind(subject)
      text = clean(subject)
      count[k]++
      body[k] = body[k] line_for(short, text) "\n"
    }

    END {
      found = 0
      for (i = 1; i <= n; i++) {
        k = order[i]
        if (count[k] > 0) {
          printf "### %s\n\n%s\n", title[k], body[k]
          found = 1
        }
      }
      if (!found) print "_No notable changes._"
    }
  '
}

# render_section <range>
render_section() {
  local range="$1"
  if [ -n "$VERSION" ]; then
    printf '## [%s] - %s\n\n' "$VERSION" "$DATE"
  else
    printf '## [Unreleased]\n\n'
  fi
  render_body "$range"
  printf '\n'
}

# ---------------------------------------------------------------------------
# --update：幂等写入 / 替换
# ---------------------------------------------------------------------------
update_file() {
  local file="$1" ver="$2" secfile="$3"
  local tmp start end total next first insert
  tmp="$(mktemp "${TMPDIR:-/tmp}/changelog.XXXXXX")"

  if [ ! -f "$file" ]; then
    printf '# Changelog\n\n%s\n' "$HEADER_ZH" > "$file"
  fi

  total="$(wc -l < "$file" | tr -d ' ')"

  # 已有同名节 -> 原地替换
  start=""
  if [ -n "$ver" ]; then
    start="$(grep -n "^## \[${ver}\]" "$file" | head -1 | cut -d: -f1 || true)"
  else
    start="$(grep -n '^## \[Unreleased\]' "$file" | head -1 | cut -d: -f1 || true)"
  fi

  if [ -n "$start" ]; then
    next="$(awk -v s="$start" 'NR > s && /^## \[/ { print NR; exit }' "$file")"
    if [ -n "$next" ]; then end=$((next - 1)); else end="$total"; fi
    if [ "$start" -gt 1 ]; then sed -n "1,$((start - 1))p" "$file" > "$tmp"; else : > "$tmp"; fi
    cat "$secfile" >> "$tmp"
    if [ "$end" -lt "$total" ]; then sed -n "$((end + 1)),\$p" "$file" >> "$tmp"; fi
    mv "$tmp" "$file"
    return 0
  fi

  # 新节：插入位置
  if [ -z "$ver" ]; then
    # [Unreleased] 永远在最前面
    first="$(grep -n '^## \[' "$file" | head -1 | cut -d: -f1 || true)"
    insert="${first:-$((total + 1))}"
  else
    # 版本节插在 [Unreleased] 之后、其他版本节之前
    unreleased="$(grep -n '^## \[Unreleased\]' "$file" | head -1 | cut -d: -f1 || true)"
    first_released="$(awk '/^## \[/ && !/^## \[Unreleased\]/ { print NR; exit }' "$file")"
    if [ -n "$first_released" ]; then
      insert="$first_released"
    elif [ -n "$unreleased" ]; then
      insert="$(awk -v s="$unreleased" 'NR > s && /^## \[/ { print NR; exit }' "$file")"
      [ -n "$insert" ] || insert="$((total + 1))"
    else
      first="$(grep -n '^## \[' "$file" | head -1 | cut -d: -f1 || true)"
      insert="${first:-$((total + 1))}"
    fi
  fi

  if [ "$insert" -le "$total" ]; then
    if [ "$insert" -gt 1 ]; then sed -n "1,$((insert - 1))p" "$file" > "$tmp"; else : > "$tmp"; fi
    # 收敛尾部多余空行，保证节之间恰好一个空行
    awk 'BEGIN{b=0} { if ($0=="") { b++; if (b>1) next } else b=0; print }' "$tmp" > "$tmp.norm"
    mv "$tmp.norm" "$tmp"
    printf '\n' >> "$tmp"
    cat "$secfile" >> "$tmp"
    sed -n "${insert},\$p" "$file" >> "$tmp"
  else
    cp "$file" "$tmp"
    printf '\n' >> "$tmp"
    cat "$secfile" >> "$tmp"
  fi

  mv "$tmp" "$file"
}

# ---------------------------------------------------------------------------
# main
# ---------------------------------------------------------------------------
if [ "$ALL" -eq 1 ]; then
  out="$(mktemp "${TMPDIR:-/tmp}/changelog.XXXXXX")"
  {
    printf '# Changelog\n\n%s\n\n' "$HEADER_ZH"
  } > "$out"

  tags="$(git tag --sort=-v:refname | grep -E '^v[0-9]' || true)"
  for t in $tags; do
    prev="$(git describe --tags --abbrev=0 "${t}^" 2>/dev/null || true)"
    if [ -n "$prev" ]; then range="$prev..$t"; else range="$t"; fi
    tdate="$(git log -1 --format=%cs "$t" 2>/dev/null || echo "$DATE")"
    VERSION="$t" DATE="$tdate" render_section "$range" >> "$out"
  done

  if [ -n "$tags" ]; then
    last="$(printf '%s\n' "$tags" | head -1)"
    VERSION="" render_section "${last}..HEAD" >> "$out"
  else
    VERSION="" render_section "HEAD" >> "$out"
  fi

  if [ -n "$UPDATE_FILE" ]; then
    mv "$out" "$UPDATE_FILE"
    echo "wrote $UPDATE_FILE" >&2
  else
    cat "$out"
    rm -f "$out"
  fi
  exit 0
fi

RANGE="$TO"
[ -n "$FROM" ] && RANGE="$FROM..$TO"

if [ -n "$UPDATE_FILE" ]; then
  secfile="$(mktemp "${TMPDIR:-/tmp}/changelog.XXXXXX")"
  render_section "$RANGE" > "$secfile"
  update_file "$UPDATE_FILE" "$VERSION" "$secfile"
  rm -f "$secfile"
  echo "updated $UPDATE_FILE" >&2
else
  render_section "$RANGE"
fi
