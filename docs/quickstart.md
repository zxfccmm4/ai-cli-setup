# 快速上手

目标：**5 分钟内装好第一个工具，并连上你自己的 API 网关。**

---

## 0. 前提

| 项 | 要求 |
|---|---|
| 系统 | Linux 或 macOS（Windows 建议 WSL2） |
| Shell | bash 3.2+（macOS 自带即可，**不需要** `brew install bash`） |
| 网络 | 能访问 `raw.githubusercontent.com`（被墙会自动切 jsDelivr 镜像） |
| 命令 | `curl` 或 `wget`；写配置需要 `node` 或 `bun` |

先体检一下：

```bash
./ai-cli-setup.sh doctor
```

会打印平台、shell、语言、缓存目录、已装命令、已装 CLI、已有配置文件。
`·` 表示没装，`✓` 表示可用 —— **没有 `✗` 就不会有硬性阻塞**。

---

## 1. 拿到脚本

**方式 A：克隆（推荐，自带离线快照）**

```bash
git clone https://github.com/zxfccmm4/ai-cli-setup.git
cd ai-cli-setup
./ai-cli-setup.sh
```

**方式 B：一行命令（不落盘，自动下载上游）**

```bash
curl -fsSL https://raw.githubusercontent.com/zxfccmm4/ai-cli-setup/main/ai-cli-setup.sh | bash
```

> 管道模式下脚本从 `/dev/tty` 读输入，所以交互向导依然可用。
> 需要传参时用 `bash -s --`：
> ```bash
> curl -fsSL .../ai-cli-setup.sh | bash -s -- all -y --base-url ... --api-key ...
> ```

**方式 C：Release 产物**

```bash
gh release download v1.0.0 -R zxfccmm4/ai-cli-setup
chmod +x ai-cli-setup.sh          # GitHub asset 不带可执行位
./ai-cli-setup.sh
```

---

## 2. 第一次运行（交互式）

```bash
./ai-cli-setup.sh
```

会依次问你：

```
Which tools do you want to set up?

  1) Pi           https://pi.dev
  2) OmO          https://omo.dev
  3) Claude Code  https://claude.ai/code
  4) Codex CLI    https://github.com/openai/codex
  5) Grok Build   https://x.ai/cli
  6) OpenCode     https://opencode.ai
  7) all of the above

choose (e.g. 1,3 or 7 for all) [7]:
```

- 输入 `1,3` → 只装 Pi 和 Claude Code
- 输入 `7` 或直接回车 → 全部

然后：

```
API endpoint base URL (e.g. https://api.example.com/v1): https://gw.example.com/v1
API key: ********
ℹ  fetching model list from the endpoint...
model ids to register (comma separated, blank = all above) [gpt-5.6,gpt-5.5,...]:
```

**API Key 输入时不回显**，之后的摘要里也只会显示 `前4****后4`。

模型列表会自动从 `<base-url>/v1/models` 拉取，直接回车表示「全部注册」。

---

## 3. 只装一个工具

```bash
./ai-cli-setup.sh pi
```

最省事的写法：**把工具名当第一个参数**。等价于 `--only pi`。

想跳过某个：

```bash
./ai-cli-setup.sh all --skip claude,codex
```

---

## 4. 完全非交互（CI / 批量部署）

```bash
./ai-cli-setup.sh all -y \
  --base-url https://gw.example.com/v1 \
  --api-key sk-xxxx \
  --models gpt-5.6,gpt-5.5,claude-sonnet-4-5
```

`-y` 下如果缺 `--base-url` 或 `--api-key`，脚本会**直接报错退出**，不会卡住等输入。

---

## 5. 先预演，再动手

```bash
./ai-cli-setup.sh all -y --base-url ... --api-key ... --dry-run
```

`--dry-run` 只打印「将要写什么」，**不落盘、不装软件**。

---

## 6. 装完怎么验证

```bash
./ai-cli-setup.sh doctor      # 看已装 CLI 与配置文件
```

然后按工具启动：

| 工具 | 验证 |
|---|---|
| Pi | `pi --version`，然后在项目里 `pi` |
| OmO | `omo --version` |
| Claude Code | `claude --version` |
| Codex CLI | `codex --version` |
| Grok Build | `grok --version` |
| OpenCode | `opencode --version` |

---

## 7. 之后想改配置

**不用重装**，加 `--skip-install`：

```bash
./ai-cli-setup.sh all --skip-install -y \
  --base-url https://new-gw.example.com/v1 \
  --api-key sk-new \
  --models a,b
```

只重写配置文件，不碰已安装的 CLI。

---

## 常见下一步

- 每个工具具体写哪些字段 → [configuration.md](./configuration.md)
- 报错、网络超时、权限问题 → [troubleshooting.md](./troubleshooting.md)
- 想改脚本 / 发版 → [development.md](./development.md)
