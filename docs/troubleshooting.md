# 常见问题 / 排错

先跑一次体检，多数问题一眼可见：

```bash
./ai-cli-setup.sh doctor
./ai-cli-setup.sh list
```

---

## 1. 安装类

### `missing --base-url`

用了 `-y` 但没给凭据。补上：

```bash
./ai-cli-setup.sh all -y --base-url https://gw.example.com/v1 --api-key sk-xxxx
```

或者去掉 `-y` 走交互。

### `unknown agent: xxx`

agent 名拼错了。可选：`pi` `omo` `omp` `claude` `codex` `grok` `opencode`，
以及 `all` / `list` / `doctor` / `help`。

注意逗号分隔**整体**要合法，`opencode,nope` 会整条被拒。

### 汇总里某个 agent 显示 `✗ … install failed`

安装步骤没产出可执行的二进制。往上翻能看到具体原因（通常是缺
`curl`/`wget`/`node`/`npm`/`bun`，或网络不通）。

**一个 agent 失败不影响其它 agent**：脚本会继续装完并配置剩下的，
最后汇总失败数量。想「首败即停」加 `--fail-fast`。

### `need curl or wget`

安装 Pi / OmO / OMP / Grok / OpenCode 需要下载。装一个：

```bash
apt-get install -y curl        # Debian/Ubuntu
apk add curl                   # Alpine
```

### `node not found; installing Node.js ...`

Pi / OmO / Codex 通过 npm 安装，OMP 通过官方 installer（回退 bun / npm），都需要 Node。
脚本按顺序尝试：已有的 `node` → macOS 的 Homebrew / Linux 的 nodesource+apt →
**官方 tarball 独立安装**（免 root、免 Homebrew，装到 `~/.local/share/pi-node/current`，
带 sha256 校验）。全部失败才会报 `node install failed`，那时请手动装：

```bash
# nvm
curl -o- https://raw.githubusercontent.com/nvm-sh/nvm/v0.40.1/install.sh | bash
nvm install 22

# 或 brew
brew install node
```

> 独立安装的 Node 只作用于本脚本与之后新开的 shell（脚本会写 PATH 到 shell rc）。
> 想立刻在当前终端用：`export PATH="$HOME/.local/share/pi-node/current/bin:$PATH"`。

### Pi 装完直接进了 pi 的界面 / 卡在那个 TUI

上游 `pi.dev/install.sh` 在 stdout 是终端时会问 `Start pi now? [Y/n]`（默认 Y）并
`exec pi`，把调用方的终端交给 pi 的 TUI。本脚本默认走 npm 安装（不会发生这件事）；
只有 npm 不可用才回退官方 installer，并**用 `setsid` 剥夺它的控制终端**，让它走非交互分支。
若看到 `cannot run the official installer without hijacking the terminal`，
说明系统缺 `setsid`/`perl`/`python3`：先手动装好 Node.js + npm 再重跑。

### OMP 安装

OMP（`@oh-my-pi/pi-coding-agent`）走官方 installer：

```bash
curl -fsSL https://omp.sh/install | sh
```

安装器会校验 sha256 并自检二进制可运行，装到 `~/.local/bin/omp`。
失败时脚本依次退到 `bun install -g @oh-my-pi/pi-coding-agent`（`~/.bun/bin`）
和 `npm install -g`。OMP 需要 **Bun ≥ 1.3.14**（或官方预编译二进制）。

### OpenCode V2 提示「当前终端先执行 source …」？

V2 格式把密钥放在 shell 环境变量里（`opencode.json` 只留 `{env:VAR}` 引用），
而写进 `.bashrc` / `.zshrc` 只对**新开的 shell** 生效。当前终端里的 opencode
读不到变量就不会发 `Authorization` 头，网关会直接 401。

按提示在**当前终端**载入一次（或直接新开一个终端）：

```bash
source ~/.bashrc        # zsh 用户：source ~/.zshrc
```

想彻底避免这一步，改用 V1 格式（密钥直写配置文件）：

```bash
AICLI_OPENCODE_V2=0 ./ai-cli-setup.sh opencode -y --skip-install \
  --base-url https://gw.example.com/v1 --api-key sk-x --models m1
```

### `✗ Claude Code … 仅支持 Linux/WSL；跳过安装`

不是 bug。Claude Code 的官方 installer 只支持 Linux / WSL，macOS 上脚本
只写配置、跳过安装。macOS 想装 CLI：

```bash
npm install -g @anthropic-ai/claude-code
```

### 软路由（OpenWrt / iStoreOS 等 musl）上装完命令 `not found`

装完后命令找不到，多是因为当前终端还没重读 `PATH`。脚本会自动把二进制
软链到 `/usr/local/bin`（或 `/usr/bin`）——这些目录本来就在 `PATH` 里，
**当前终端与新终端都能直接敲命令**。若仍是 `not found`，手动执行：

```bash
export PATH="$HOME/.local/bin:$HOME/.grok/bin:$HOME/.opencode/bin:$PATH"
```

### 软路由上 Pi / OmO / OMP / Codex 被跳过（`needs Node.js (musl)`）

不是 bug。OpenWrt/iStoreOS 是 musl 系统，无法直接运行官方 glibc 版 Node.js，
而这几个 agent 依赖它。脚本会在**安装阶段**直接标记为 `-`（跳过、不算失败），
但**仍会写入它们的配置文件**，方便你在别处（如 Debian/Alpine 容器）运行。

想在本机用，请在容器里装 node：

```bash
docker run -it --rm -v "$PWD:/w" -w /w debian:bookworm bash
# 容器内：apt-get update && apt-get install -y nodejs npm
```

已装 musl 版 node 或 bun 的机器不会被跳过（脚本会尊重你已有的运行时）。

---

## 2. 网络类

### 模型列表拉不出来

脚本请求 `<base-url>/v1/models`，拿不到就退化成手动输入。直接指定：

```bash
--models gpt-5.6,gpt-5.5
```

也可以自己确认端点：

```bash
curl -H "Authorization: Bearer $KEY" https://gw.example.com/v1/models | head
```

> 有些网关不实现 `/v1/models`，这**不影响**使用，只是需要手填模型名。

### 安装脚本下载超时

安装全部走官方渠道，代理/镜像请按各自的官方文档配置（例如 npm 用
`npm config set registry …`，`curl` 用 `HTTPS_PROXY`）。

---

## 3. 配置类

### 中文报错 `unbound variable`

如果你**自己改过脚本**并在中文前面直接写 `$var`，bash 3.2 + `set -u` 会把
中文字节当成变量名的一部分。改成 `${var}`：

```bash
echo "$ref失败"      # ✗ 报错
echo "${ref}失败"    # ✓
```

CI 里有自动检查（`scripts/check-multibyte-vars.py`）。

### `opencode.json` 里 provider 名字怪怪的

未知网关会由 host 推导，`https://my.gw.io/v1` → `my-gw-io`。
想改就换 base-url，或直接改配置里的 provider id。

### OpenCode 写成了 V1 格式，但我装的是 2.x？

脚本按 `opencode --version` 的主版本判断，输出形如 `opencode v2.0.26`。
如果自动判断不合预期，显式指定：

```bash
AICLI_OPENCODE_V2=1 ./ai-cli-setup.sh opencode -y --skip-install \
  --base-url https://gw.example.com/v1 --api-key sk-x --models m1
```

V2 会把密钥写进 shell 配置（`export AICLI_<PROVIDER>_API_KEY=…`）而不是
`opencode.json`；想取消引用，删掉那行并改回 V1 格式即可。

### omp 的密钥是明文？

是的，这是 omp 的限制：`models.yml` 不做环境变量插值（`${VAR}` 会被原样当
密钥发出去），也没有 `{env:}` 引用语法。脚本强制 `chmod 600` 保护该文件。

### 我的 `opencode.json` / `settings.json` 里其他配置会不会丢？

不会。OpenCode、Claude Code、omp 都是**合并写入**：`plugin` / `mcp` / 其它
provider / `permissions` / `theme` 等全部保留，写入前还会备份成
`<文件>.bak.<时间戳>`。

### 想改回旧配置

```bash
ls ~/.grok/config.toml.bak.*
cp ~/.grok/config.toml.bak.20261010120000 ~/.grok/config.toml

ls ~/.config/opencode/opencode.json.bak.*
cp ~/.config/opencode/opencode.json.bak.20261010120000 ~/.config/opencode/opencode.json
```

---

## 4. 权限类

### 提示 `permission denied`

Release 下载的 asset 不带可执行位：

```bash
chmod +x ai-cli-setup.sh changelog.sh
```

### 配置里含密钥，权限应该是 600

脚本写入时会自动 `chmod 600`。手动确认：

```bash
ls -l ~/.grok/config.toml ~/.config/opencode/opencode.json ~/.omp/agent/models.yml
# -rw-------  ✓
```

---

## 5. 行为类

### `--dry-run` 真的什么都没写吗？

是。不建目录、不写文件、不产生备份、不执行 agent 二进制。想验证：

```bash
./ai-cli-setup.sh all -y --dry-run --base-url ... --api-key ...
find ~ -name '*.bak.*' -newermt '-1 minute'     # 应该为空
```

### 一个 agent 失败了，其他会继续吗？

会。每个 agent 的安装失败只标记它自己为 `✗`，其余照常安装与配置，
最后给出汇总。想「第一个失败就停」加 `--fail-fast`。

### 怎么只重跑失败的某个 agent？

```bash
./ai-cli-setup.sh codex -y --base-url ... --api-key ...
```

### 只想改配置，不想重装 CLI

```bash
./ai-cli-setup.sh all --skip-install -y --base-url ... --api-key ...
```

### 想换默认模型

```bash
./ai-cli-setup.sh all --skip-install -y \
  --base-url https://gw.example.com/v1 --api-key sk-xxxx \
  --model group/auto-claude-sonnet-5-5
```

---

## 6. 还是不行？

收集这些信息再提 issue：

```bash
./ai-cli-setup.sh --version
./ai-cli-setup.sh doctor
./ai-cli-setup.sh list
```

以及失败 agent 的完整输出（汇总会列出每个 agent 的失败状态）。

提 issue：<https://github.com/zxfccmm4/ai-cli-setup/issues>

> ⚠️ 贴日志前先删掉 `--api-key` 后面的明文密钥。掩码只作用于交互输入，
> 命令行参数和脚本输出里仍可能是明文。
