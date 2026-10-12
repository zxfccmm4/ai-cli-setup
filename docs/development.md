# 开发与发布

面向想改代码、跑测试、发版的贡献者。

---

## 1. 仓库结构

```
.
├── ai-cli-setup.sh              # 唯一的主脚本（全自研，无上游依赖）
├── scripts/
│   ├── changelog.sh             # CHANGELOG 生成器
│   └── check-multibyte-vars.py  # bash 3.2 多字节变量检查
├── docs/                        # 本目录
├── .github/workflows/
│   ├── ci.yml                   # 语法 + shellcheck + 双平台冒烟
│   └── release.yml              # tag 触发：verify → build → release
├── CHANGELOG.md                 # 由 scripts/changelog.sh 生成
└── README.md
```

**约定**：所有安装与配置逻辑都在 `ai-cli-setup.sh` 里，不下载也不包装任何第三方
安装脚本；各 agent 走**官方 installer 或官方 npm 包**。

---

## 2. 本地开发

```bash
git clone https://github.com/zxfccmm4/ai-cli-setup.git
cd ai-cli-setup
./ai-cli-setup.sh doctor      # 先看环境
./ai-cli-setup.sh list        # 看各 agent 是否已装
```

### 主脚本的结构（从上到下）

| 段落 | 内容 |
|---|---|
| 1–5 | 全局状态、i18n、输出 helper、TTY/掩码输入、平台检测 |
| 6 | **agent 清单（manifest）**：`ALL_AGENTS` / `agent_bin` / `agent_title` / `agent_needs_models` … |
| 7 | 安装：`install_<agent>` + `post_install_check` |
| 8 | 模型列表（`/v1/models`） |
| 9 | JSON 工具（无 jq 依赖） |
| 10 | 配置写入：每个 agent 一个 `write_*` 函数 |
| 11–12 | 交互（语言 → agent）、凭据收集 |
| 13 | 子命令（`cmd_list` / `cmd_doctor` / `usage`） |
| 14 | 参数解析、`main` |

### 加一个新 agent 要改哪里

以加 `foo` 为例：

1. **manifest（第 6 段）**：`ALL_AGENTS` 加 `foo`；`agent_valid` / `agent_title` /
   `agent_homepage` / `agent_bin` 各加一个 `foo)` 分支；按需在
   `agent_needs_models` / `agent_needs_model` / `agent_linux_only` /
   `agent_unrunnable_here` 里登记。
2. **安装（第 7 段）**：写 `install_foo()`，**返回非 0 表示失败**
   （不要用 `die`，见下文「坑」）。
3. **`install_agent`**：在 `case` 里加 `foo) install_foo || rc=$? ;;`。
4. **配置（第 10 段）**：写 `write_foo()`，并在 `configure_agent` 的 `case` 里分派。
5. **文档**：`usage()` 的 AGENTS / CONFIG FILES 表、`cmd_doctor` 的配置文件列表、
   `README.md` 的 agent 矩阵。

---

## 3. 测试

### 本地全量检查（等价于 CI）

```bash
# 1. 语法
bash -n ai-cli-setup.sh
bash -n scripts/changelog.sh

# 2. shellcheck
shellcheck -S warning ai-cli-setup.sh scripts/changelog.sh

# 3. 多字节变量（bash 3.2）
python3 scripts/check-multibyte-vars.py ai-cli-setup.sh scripts/changelog.sh

# 4. 基本命令
./ai-cli-setup.sh --version
./ai-cli-setup.sh --help >/dev/null
./ai-cli-setup.sh list >/dev/null
./ai-cli-setup.sh doctor >/dev/null

# 5. CHANGELOG
./scripts/changelog.sh --all --update CHANGELOG.md
git diff --exit-code CHANGELOG.md
```

### 在隔离 HOME 里真写配置

CI 的做法：把 `HOME` **和** `XDG_CONFIG_HOME` 都指到临时目录
（GitHub runner 预设了 `XDG_CONFIG_HOME`，只改 `HOME` 会写错地方）。

```bash
export HOME=/tmp/fakehome XDG_CONFIG_HOME=/tmp/fakehome/.config
mkdir -p "$HOME"

./ai-cli-setup.sh opencode -y --skip-install \
  --base-url https://gw.example.com/v1 \
  --api-key sk-test \
  --models gpt-5,gpt-5-mini

node -e '
const c = require(process.env.HOME + "/.config/opencode/opencode.json");
const p = (c.provider || c.providers)["gw-example-com"];
const opts = p.options || p.settings;
if (opts.baseURL !== "https://gw.example.com/v1") throw new Error("baseURL");
if (!p.models["gpt-5"]) throw new Error("models");
console.log("opencode.json OK");
'
```

### 手动测某个 agent

```bash
./ai-cli-setup.sh grok -y --dry-run --skip-install \
  --base-url https://gw.example.com/v1 --api-key sk-x
```

`--dry-run` 必须做到「零落盘」：不建目录、不写备份、不执行 agent 二进制
（`opencode --version` 会自己创建 cache/state/log 目录，所以 V2 探测在
dry-run 下改为只看配置文件）。

### 模拟「没有 node / curl」的精简系统

用只含基础命令的临时 PATH 跑，能覆盖 musl/BusyBox 分支：

```bash
mkdir -p /tmp/shim/bin
for c in bash sh env sed grep cut tr mktemp date mkdir mv cp chmod printf uname id stty; do
  ln -sf "$(command -v $c)" /tmp/shim/bin/$c
done
HOME=/tmp/h PATH=/tmp/shim/bin /tmp/shim/bin/bash ./ai-cli-setup.sh pi -y \
  --base-url https://gw.example.com/v1 --api-key sk-x --models m1
```

---

## 4. 三个必须记住的坑

### ① `$var` 后面紧跟中文 → 必须写 `${var}`

bash 3.2 + `set -u` 会把中文首字节当成变量名的一部分，报 `unbound variable`：

```bash
err "下载 $file 失败（$repo@$ref）"       # ✗
err "下载 ${file} 失败（${repo}@${ref}）"  # ✓
```

CI 有自动检查（`scripts/check-multibyte-vars.py`）。

### ② 依赖缺失要「返回失败」，不要 `die`

`die` 会直接 `exit 1`，把整个流程带走——后面的 agent 连配置都不会写。
`install_<agent>` / `ensure_node` / `need_dl` 一律 `return 1`，由
`install_agent` 收口成该 agent 的 `FAIL`；「首败即停」交给 `--fail-fast`。
安装失败也必须如实报 `FAIL`：`post_install_check` 找不到可执行二进制时返回 1。

### ③ 隔离测试要同时设 `XDG_CONFIG_HOME`

否则 OpenCode 的配置会写到 runner 的真实 HOME 里，测试找不到文件。

---

## 5. CI

`.github/workflows/ci.yml`，两个 job：

**`lint`**（ubuntu-latest）
- `bash -n`
- `shellcheck -S warning`
- `$var` + 中文 检查
- CHANGELOG 格式检查（硬性）+ 新鲜度检查（告警）
- `changelog.sh` 幂等测试

**`smoke`**（ubuntu + macos 矩阵）
- `--version` / `--help` / `list` / `doctor`
- 隔离 HOME 下 `all -y --skip-install` 真写全部配置文件，校验内容与 `600` 权限
- `--dry-run` 零落盘、`-y` 缺凭据报错、未知 agent 被拒
- 交互流程（`AICLI_ASSUME_TTY`）与菜单重试
- 合并不丢键（`plugin` / 其它 provider 保留）
- 管道模式（`cat ... | bash -s --`）
- macOS 系统 bash 3.2 兼容性

---

## 6. CHANGELOG

由 `scripts/changelog.sh` 从 git 历史生成，按约定式提交分桶：

```bash
./scripts/changelog.sh --all --update CHANGELOG.md
```

提交信息请用 `feat:` / `fix:` / `perf:` / `refactor:` / `docs:` / `test:` /
`ci:` / `build:` / `chore:`，否则归到 `Other`。

生成器会**跳过** `chore(release):` / `docs(changelog):` / `chore: release`
开头的提交，避免自我引用死循环。

> 注意：`--all` 依赖 git tag。打 tag 后 `--all` 的输出会变，
> 所以 CI 里新鲜度检查只是**告警**，格式检查才硬性失败。

---

## 7. 发版

```bash
# 1. 同步 CHANGELOG
./scripts/changelog.sh --all --update CHANGELOG.md
git add CHANGELOG.md
git commit -m "docs(changelog): 同步变更记录"
git push origin main

# 2. 打 tag 并推送（触发 Release workflow）
git tag -a v2.1.0 -m "v2.1.0 — 简要说明"
git push origin v2.1.0
```

`release.yml` 有两条渠道：

**稳定版（手动打 tag）** —— 1. **verify** 语法 / shellcheck / 冒烟，不过就不发；
2. **build** 产出 `ai-cli-setup.sh`、`changelog.sh`、`CHANGELOG.md`、`README.md`、
`LICENSE`、`SHA256SUMS`、`VERSION.txt`，并在 CI 内自校验；
3. **release** 从 `CHANGELOG.md` 摘出本版本那节做 release notes，创建 Release。

已发布过的版本可重跑（`gh release edit` + `upload --clobber`）。
也可以手动 `workflow_dispatch` 只做构建校验、不发布。

**滚动预发布（每次 push main 自动）** —— `rolling` job 重建 `latest` 这个
移动 tag 的 prerelease：产物始终对应 main 最新提交，标为 prerelease 且
`--latest=false`，不会抢走稳定版的 "Latest" 徽章。因此**每次提交都会自动更新
Release**，而稳定版本仍按语义化版本手动发布。

> 注意：`latest` 是**移动 tag**。`changelog.sh` 里用
> `git describe --match 'v[0-9]*'` 限定只认版本 tag，否则 `latest` 会被当成
> 上一个版本，导致新版本节只覆盖极少量提交、历史内容丢失。新增任何非版本
> tag 时都要保持这个 `--match`。

发布后自检：

```bash
gh release download v2.1.1 -R zxfccmm4/ai-cli-setup
chmod +x ai-cli-setup.sh
shasum -a 256 -c SHA256SUMS
./ai-cli-setup.sh --version
```

---

## 8. 版本号

`VERSION` 在脚本顶部（当前 `2.1.1`）。改脚本行为就同步 bump，并在
`CHANGELOG.md` 记录；脚本本身不联网检查更新。

---

## 9. 代码风格

- **bash 3.2 兼容**（macOS 自带）。不要用 `mapfile`、`declare -A`、`${var,,}` 等
- 所有交互读 `/dev/tty`（支持 `curl | bash`）
- 所有面向用户的输出走 `stderr`（`>&2`），只有数据走 stdout
- 面向用户的文案用 `lc 'english' '中文'` 双语
- 写文件用 `mktemp` + `mv` 原子替换，敏感文件 `chmod 600`
- 改文件前先备份；`--dry-run` 下不备份、不建目录、不落盘
