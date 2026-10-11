# 快速上手

目标：**5 分钟内装好第一个工具，并连上你自己的 API 网关。**

---

## 0. 前提

| 项 | 要求 |
|---|---|
| 系统 | Linux 或 macOS（Windows 建议 WSL2） |
| Shell | bash 3.2+（macOS 自带即可，**不需要** `brew install bash`） |
| 网络 | 能访问各 agent 的官方安装源 |
| 命令 | `curl` 或 `wget`；写 Pi / OmO / Codex / OMP 的配置建议有 `node`（无 node 时脚本有纯 bash 兜底） |

先体检一下：

```bash
./ai-cli-setup.sh doctor
```

会打印平台、用户、语言、可用命令、已装 CLI、已有配置文件。
`·` 表示没装，`✓` 表示可用。

---

## 1. 拿到脚本

**方式 A：克隆（推荐，方便看代码）**

```bash
git clone https://github.com/zxfccmm4/ai-cli-setup.git
cd ai-cli-setup
./ai-cli-setup.sh
```

**方式 B：一行命令**

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
gh release download v2.1.0 -R zxfccmm4/ai-cli-setup
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
Select language  /  选择语言
  1) English
  2) 中文 (Chinese)

要安装哪些 AI agent？
  1) Pi           https://pi.dev
  2) OmO          https://omo.dev
  3) OMP          https://omp.sh
  4) Claude Code  （仅 Linux/WSL）
  5) Codex CLI    https://github.com/openai/codex
  6) Grok Build   https://x.ai/cli
  7) OpenCode     https://opencode.ai
  8) 以上全部

  单个数字 = 单选   |   1,3 或 1-3 = 多选   |   回车 或 a = 全部
```

- 输入 `1,3` → 只装 Pi 和 OMP
- 输入 `8` 或直接回车 → 全部

然后：

```
接口 base URL: https://gw.example.com/v1
API key: sk-**************xyz
ℹ  正在从端点获取模型列表...
要写入的模型 id（逗号分隔，留空 = 全部）:
```

**API Key 输入时实时掩码**（只显示前 3 位 + 星号 + 后 3 位），粘贴也不回显明文。

模型列表会自动从 `<base-url>/v1/models` 拉取，直接回车表示「全部注册」。

---

## 3. 只装某几个工具

```bash
./ai-cli-setup.sh pi
./ai-cli-setup.sh pi,omp,opencode
```

最省事的写法：**把 agent 名当位置参数**，逗号分隔可多选；
`all` 表示全部。

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

`--dry-run` 只打印「将要写什么」，**不落盘、不建目录、不装软件**。

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
| OMP | `omp --version` |
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
