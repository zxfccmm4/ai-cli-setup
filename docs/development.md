# 开发与发布

面向想改代码、跑测试、发版的贡献者。

---

## 1. 仓库结构

```
.
├── ai-cli-setup.sh              # 统一入口（唯一的主脚本，~1300 行）
├── scripts/
│   └── changelog.sh             # CHANGELOG 生成器
├── upstream/                    # 5 个上游仓库的未修改快照（离线可用）
│   ├── pi-setup/
│   ├── omo-setup/
│   ├── claude-code-linux-installer/
│   ├── deploy-codex/
│   └── GrokBuild/
├── docs/                        # 本目录
├── .github/workflows/
│   ├── ci.yml                   # 语法 + shellcheck + 双平台冒烟
│   └── release.yml              # tag 触发：verify → build → release
├── VERSIONS.md                  # --pin 用的上游提交锁定表
├── CHANGELOG.md                 # 由 scripts/changelog.sh 生成
└── README.md
```

**约定**：`upstream/` 里的文件**永远不改**，直接照搬上游。
所有整合逻辑都在 `ai-cli-setup.sh` 里。

---

## 2. 本地开发

```bash
git clone https://github.com/zxfccmm4/ai-cli-setup.git
cd ai-cli-setup
./ai-cli-setup.sh doctor      # 先看环境
./ai-cli-setup.sh list        # 看工具清单与缓存状态
```

### 主脚本的结构（从上到下）

| 段落 | 内容 |
|---|---|
| 1–5 | 默认值、i18n、输出 helper、TTY、平台检测 |
| 6 | **工具清单（manifest）**：`tool_repo` / `tool_files` / `tool_entry` / … |
| 7 | 下载与缓存 |
| 8 | 模型列表（`/v1/models`） |
| 9 | 凭据收集 |
| 10 | Grok 配置写入 |
| 10b | **OpenCode**：安装 + `opencode.json` 合并写入 |
| 11 | 运行单个工具（`run_tool`） |
| 12 | 子命令（`cmd_list` / `cmd_doctor` / …） |
| 13–14 | 参数解析、main |

### 加一个新工具要改哪里

以加 `foo` 为例，在 **manifest 段落** 补几处：

```bash
ALL_TOOLS="pi omo claude codex grok opencode foo"     # 1. 加进列表

tool_repo()  { ... foo) printf 'foo-setup' ;; }       # 2. 上游仓库名
tool_pin()   { ... foo) printf '%s' "$PIN_foo" ;; }   # 3. --pin 提交
tool_files() { ... foo) printf '%s\n' foo-setup.sh ;; }  # 4. 需要下载的文件
tool_entry() { ... foo) printf 'foo-setup.sh' ;; }    # 5. 入口脚本
tool_title() { ... foo) printf 'Foo' ;; }             # 6. 显示名
tool_homepage(){ ... foo) printf 'https://foo.dev' ;; } # 7. 主页
tool_valid() { ... pi|...|foo) return 0 ;; }          # 8. 合法工具
```

再按需补：`tool_supports_lang` / `tool_supports_dry_run` / `tool_needs_root`
/ `tool_env_prefix` / `tool_extra_args`，以及交互菜单 `cmd_interactive_pick`
里的编号。

如果是**没有上游仓库**的工具（像 `opencode`），额外加：

```bash
tool_selfmanaged() { case "$1" in opencode) return 0 ;; *) return 1 ;; esac; }
```

并在 `run_tool` 里分派到你自己的实现。

---

## 3. 测试

### 本地全量检查（等价于 CI）

```bash
# 1. 语法
bash -n ai-cli-setup.sh
bash -n scripts/changelog.sh

# 2. shellcheck
shellcheck -S warning ai-cli-setup.sh scripts/changelog.sh

# 3. 基本命令
./ai-cli-setup.sh --version
./ai-cli-setup.sh --help >/dev/null
./ai-cli-setup.sh list >/dev/null
./ai-cli-setup.sh doctor >/dev/null

# 4. 离线快照
./ai-cli-setup.sh download --only pi,omo,codex,grok

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
  --api-key sk-test-123456 \
  --models gpt-5,gpt-5-mini

node -e '
const c = require(process.env.HOME + "/.config/opencode/opencode.json");
const p = c.provider["gw-example-com"];
if (p.options.baseURL !== "https://gw.example.com/v1") throw new Error("baseURL");
if (!p.models["gpt-5"]) throw new Error("models");
if (c.model !== "gw-example-com/gpt-5") throw new Error("default model");
console.log("opencode.json OK");
'
```

### 手动测某个工具

```bash
./ai-cli-setup.sh grok -y --dry-run --skip-install \
  --base-url https://gw.example.com/v1 --api-key sk-x
```

---

## 4. 两个必须记住的坑

### ① `$var` 后面紧跟中文 → 必须写 `${var}`

bash 3.2 + `set -u` 会把中文首字节当成变量名的一部分，报 `unbound variable`：

```bash
err "下载 $file 失败（$repo@$ref）"     # ✗
err "下载 ${file} 失败（${repo}@${ref}）"  # ✓
```

CI 有自动检查（`No bare $var before multibyte text`）。

### ② 隔离测试要同时设 `XDG_CONFIG_HOME`

否则 OpenCode 的配置会写到 runner 的真实 HOME 里，测试找不到文件。

---

## 5. CI

`.github/workflows/ci.yml`，两个 job：

**`lint`**（ubuntu-latest）
- 自有脚本 `bash -n`
- `shellcheck -S warning`
- `$var` + 中文 检查
- CHANGELOG 格式检查（硬性）+ 新鲜度检查（告警）
- `changelog.sh` 幂等测试
- 上游快照语法检查（仅信息性，`continue-on-error`）

**`smoke`**（ubuntu + macos 矩阵）
- `--version` / `--help` / `list` / `doctor`
- 离线快照解析
- 隔离 HOME 下真写 `opencode.json`、`~/.grok/config.toml`
- 校验内容、`600` 权限、备份文件、JSON 合并不丢键
- `--dry-run` 不落盘
- `-y` 缺凭据报错、未知工具被拒
- 逗号分隔工具列表
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
git tag -a v1.1.0 -m "v1.1.0 — 简要说明"
git push origin v1.1.0
```

`release.yml` 会：

1. **verify** —— 语法 / shellcheck / 冒烟，不过就不发
2. **build** —— 产出 `ai-cli-setup.sh`、`changelog.sh`、`CHANGELOG.md`、
   `README.md`、`LICENSE`、`SHA256SUMS`、`VERSION.txt`，并在 CI 内自校验
3. **release** —— 从 `CHANGELOG.md` 摘出本版本那节做 release notes，创建 Release

已发布过的版本可重跑（`gh release edit` + `upload --clobber`）。
也可以手动 `workflow_dispatch` 只做构建校验、不发布。

发布后自检：

```bash
gh release download v1.1.0 -R zxfccmm4/ai-cli-setup
chmod +x ai-cli-setup.sh
shasum -a 256 -c SHA256SUMS
./ai-cli-setup.sh --version
```

---

## 8. 更新上游快照

上游更新后，刷新 `upstream/` 与 `VERSIONS.md`：

```bash
for r in pi-setup omo-setup claude-code-linux-installer deploy-codex GrokBuild; do
  echo "$r $(git ls-remote https://github.com/zxfccmm4/$r main | cut -f1)"
done
```

把新提交写进 `VERSIONS.md` 和 `ai-cli-setup.sh` 顶部的 `PIN_*` 变量，
然后重新拉取 `upstream/` 下对应文件。

---

## 9. 代码风格

- **bash 3.2 兼容**（macOS 自带）。不要用 `mapfile`、`declare -A`、`${var,,}` 等
- 所有交互读 `/dev/tty`（支持 `curl | bash`）
- 所有面向用户的输出走 `stderr`（`>&2`），只有数据走 stdout
- 面向用户的文案用 `lc 'english' '中文'` 双语
- 写文件用 `mktemp` + `mv` 原子替换，敏感文件 `chmod 600`
- 改文件前先备份
