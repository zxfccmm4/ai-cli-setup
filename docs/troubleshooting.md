# 常见问题 / 排错

先跑一次体检，多数问题一眼可见：

```bash
./ai-cli-setup.sh doctor
./ai-cli-setup.sh list
```

---

## 1. 安装类

### `missing --base-url (required in non-interactive mode)`

用了 `-y` 但没给凭据。补上：

```bash
./ai-cli-setup.sh all -y --base-url https://gw.example.com/v1 --api-key sk-xxxx
```

或者去掉 `-y` 走交互。

### `unknown command or tool: xxx`

工具名拼错了。可选：`pi` `omo` `claude` `codex` `grok` `opencode`，
以及 `all` / `list` / `doctor` / `download` / `help`。

注意逗号分隔**整体**要合法，`opencode,nope` 会整条被拒。

### `✗ Claude Code FAIL(1)` —— `this script only supports Linux/WSL.`

不是 bug。上游 `claude-code-linux-installer` 只支持 Linux / WSL，
macOS 上请用官方安装方式：

```bash
npm install -g @anthropic-ai/claude-code
```

其余工具不受影响（每个工具独立子 shell，失败不中断）。

### `✗ 在 Linux 上安装 Codex CLI 需要 sudo`

Codex 上游要写系统路径。脚本会提示用 `sudo` 重跑；也可以显式跳过：

```bash
./ai-cli-setup.sh all --skip codex
```

### `need node or bun to write pi config`

写配置阶段需要 Node 或 Bun：

```bash
# 用 nvm
curl -o- https://raw.githubusercontent.com/nvm-sh/nvm/v0.40.1/install.sh | bash
nvm install 22

# 或 brew
brew install node
```

### 软路由（OpenWrt / iStoreOS 等 musl）上装完 `claude` / `grok` 提示 `not found`

装完后命令找不到，多是因为当前终端还没重读 `PATH`。脚本现在会自动把二进制
软链到 `/usr/local/bin`（或 `/usr/bin`）——这些目录本来就在 `PATH` 里，**当前终端
与新终端都能直接敲命令**。若仍是 `not found`，手动执行：

```bash
export PATH="$HOME/.local/bin:$HOME/.grok/bin:$HOME/.opencode/bin:$PATH"
```

### 软路由上 Pi / OmO / Codex 被跳过（`needs Node.js (musl)`）

不是 bug。OpenWrt/iStoreOS 是 musl 系统，无法直接运行官方 glibc 版 Node.js，
而 Pi / OmO / Codex 依赖它。脚本会在**安装阶段**直接标记为 `-`（跳过、不算失败），
但**仍会写入它们的配置文件**，方便你在别处（如 Debian/Alpine 容器）运行。

想在本机用，请在容器里装 node：

```bash
docker run -it --rm -v "$PWD:/w" -w /w debian:bookworm bash
# 容器内：apt-get update && apt-get install -y nodejs npm
```

### 软路由上 OmO 配置失败 `生成 models.json 失败（需要 node/python3）`

已在较新版本修复：Pi / OmO 的 `models.json` 现在有**纯 bash 兜底**，
即使系统完全没有 node/python3 也能正确生成（与 OpenCode 的兜底一致）。
用最新脚本重跑即可：

```bash
curl -fsSL https://raw.githubusercontent.com/zxfccmm4/ai-cli-setup/main/ai-cli-setup.sh | bash
```

---

## 2. 网络类

### `failed to download xxx from repo@main`

脚本会依次尝试：

1. `raw.githubusercontent.com`
2. `cdn.jsdelivr.net`（镜像）

两个都失败时按下面顺序排查。

**a. 先确认网络本身**

```bash
curl -I https://raw.githubusercontent.com/zxfccmm4/pi-setup/main/pi-setup.sh
curl -I https://cdn.jsdelivr.net/gh/zxfccmm4/pi-setup@main/pi-setup.sh
```

**b. 用仓库自带快照（完全离线）**

克隆方式拿到脚本时，`upstream/` 里已有全部上游文件，脚本**优先用本地快照**：

```bash
git clone https://github.com/zxfccmm4/ai-cli-setup.git
cd ai-cli-setup
./ai-cli-setup.sh list        # cached 列会显示 local
./ai-cli-setup.sh all -y --base-url ... --api-key ...
```

**c. 走内网镜像**

```bash
AICLI_RAW_HOST=https://git.example.com/raw \
AICLI_JSD_HOST=https://cdn.example.com/gh \
AICLI_OWNER=my-mirror \
./ai-cli-setup.sh all
```

**d. 强制重下 / 清缓存**

```bash
./ai-cli-setup.sh all --refresh      # 忽略缓存
rm -rf ~/.cache/ai-cli-setup         # 彻底清空
```

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

---

## 3. 配置类

### 中文报错 `unbound variable`

如果你**自己改过脚本**并在中文前面直接写 `$var`，bash 3.2 + `set -u` 会把
中文字节当成变量名的一部分。改成 `${var}`：

```bash
echo "$ref失败"      # ✗ 报错
echo "${ref}失败"    # ✓
```

CI 里有自动检查（`No bare $var before multibyte text`）。

### `opencode.json` 里 provider 名字怪怪的

未知网关会由 host 推导，`https://my.gw.io/v1` → `my-custom-gw-io`。
想改就显式指定：

```bash
--opencode-provider mygw --opencode-provider-name "My Gateway"
```

### 我的 `opencode.json` 里其他配置会不会丢？

不会。脚本是**合并写入**，`plugin` / `mcp` / 其他 provider 全部保留，
写入前还会备份成 `opencode.json.bak.<时间戳>`。

### 想改回旧配置

```bash
ls ~/.grok/config.toml.bak.*
cp ~/.grok/config.toml.bak.20261010120000 ~/.grok/config.toml

ls ~/.config/opencode/opencode.json.bak.*
cp ~/.config/opencode/opencode.json.bak.20261010120000 ~/.config/opencode/opencode.json
```

Codex 有内置回滚：

```bash
./ai-cli-setup.sh codex -- --restore
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
ls -l ~/.grok/config.toml ~/.config/opencode/opencode.json
# -rw-------  ✓
```

自己修：

```bash
chmod 600 ~/.grok/config.toml ~/.config/opencode/opencode.json
```

---

## 5. 行为类

### `--dry-run` 真的什么都没写吗？

是。它只打印计划，不写文件、不装软件。想验证：

```bash
./ai-cli-setup.sh all -y --dry-run --base-url ... --api-key ...
ls -l ~/.grok/config.toml ~/.config/opencode/opencode.json
```

### 一个工具失败了，其他会继续吗？

会。每个工具在独立子 shell 里跑，最后给汇总。
想「第一个失败就停」加 `--fail-fast`。

### 怎么只重跑失败的某个工具？

```bash
./ai-cli-setup.sh codex -y --base-url ... --api-key ...
```

### 只想改配置，不想重装 CLI

```bash
./ai-cli-setup.sh all --skip-install -y --base-url ... --api-key ...
```

### 参数透传给上游

`--` 之后原样转发：

```bash
./ai-cli-setup.sh codex -- --restore
./ai-cli-setup.sh codex -- --uninstall
./ai-cli-setup.sh omo   -- --preset kimi-glm --memory on
./ai-cli-setup.sh pi    -- --theme dark
```

### 想固定上游版本（可复现）

```bash
./ai-cli-setup.sh all --pin
```

用的是 [VERSIONS.md](../VERSIONS.md) 里记录并验证过的提交。
想指定别的 ref：

```bash
./ai-cli-setup.sh all --ref v1.2.3
```

---

## 6. 还是不行？

收集这些信息再提 issue：

```bash
./ai-cli-setup.sh --version
./ai-cli-setup.sh doctor
./ai-cli-setup.sh list
```

以及失败工具的完整输出（脚本的汇总会列出每个工具的退出码）。

提 issue：<https://github.com/zxfccmm4/ai-cli-setup/issues>

> ⚠️ **提交日志前先打码 API Key** —— 摘要里脚本已经打码，
> 但你自己贴的完整输出可能包含明文。
