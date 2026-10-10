# 配置详解

这一页讲清楚：**你给的参数，最后变成了什么。**

---

## 1. 参数 → 环境变量映射

脚本把你统一输入的凭据，翻译成各上游认识的名字：

| 统一参数 | pi | omo | claude | codex | grok | opencode |
|---|---|---|---|---|---|---|
| `--base-url` | `PISETUP_BASE_URL` | `OMO_BASE_URL` | `CLAUDE_BASE_URL` | `CODEX_BASE_URL` | 写 `config.toml` | 写 `opencode.json` |
| `--api-key` | `PISETUP_API_KEY` | `OMO_API_KEY` | `CLAUDE_API_KEY` | `CODEX_API_KEY` | 写 `config.toml` | 写 `opencode.json` |
| `--models` | `PISETUP_MODELS` | `OMO_MODELS` | — | — | — | `provider.models` |
| `--model` | — | — | `CLAUDE_MODEL` | `CODEX_MODEL` | 写 `config.toml` | `model`（默认取 models 第一个） |
| `--lang` | `PISETUP_LANG` | `OMO_LANG` | `CLAUDE_LANG` | — | — | — |

也就是说：**pi / omo / claude / codex 是「传环境变量」，grok / opencode 是「本脚本直接写文件」。**

---

## 2. 各工具写什么文件

### `pi` → `~/.pi/agent/models.json` + `settings.json`

由上游 `pi-config.mjs` 写入。整合脚本只传参，其余交给上游。

### `omo` → `~/.omo/agent/*` + `~/.omo/omo.jsonc`

同上，由 `omo-config.mjs` 写入。多智能体（`--preset` / `--agent` / `--category`）等
高级参数目前需要通过 `--` 透传：

```bash
./ai-cli-setup.sh omo -- --preset kimi-glm --memory on
```

### `claude` → shell 配置 或 `~/.claude/settings.json`

上游支持 `--config-mode shell|settings`，默认 `shell`（写进 `.zshrc` / `.bashrc` 的
`ANTHROPIC_*` 变量）。**仅在 Linux / WSL 可用** —— macOS 上会明确报错退出。

### `codex` → `~/.codex/config.toml` + `~/.codex/auth.json`

上游生成，包含 `model_provider` / `wire_api` / `model_catalog_json` 等。
写入前用 `python3` 校验 TOML/JSON，失败**不会覆盖原文件**。
Linux 上需要 root（脚本会提示用 `sudo` 重跑）。

### `grok` → `~/.grok/config.toml`

**这是本脚本自己生成的**（上游 `install-config.sh` 只有交互向导）。
实际产物（`--grok-alias MyGrok --grok-search on`）：

```toml
[cli]
installer = "internal"

[models]
default = "MyGrok"
default_reasoning_effort = "high"
web_search = "MyGrok"          # 仅 --grok-search on 时出现

[model.MyGrok]
model = "grok-4.7"             # 由 --model 控制
base_url = "https://gw.example.com/v1"
name = "grok-4.7"
api_key = "sk-xxxx"
context_window = 500000        # AICLI_GROK_CONTEXT_WINDOW 可覆盖
supports_reasoning_effort = true
reasoning_efforts = ["low", "medium", "high"]
api_backend = "responses"          # 仅 search on
supports_backend_search = true     # 仅 search on

[features]
telemetry = false
feedback = false
```

安全措施：原子写入（先写临时文件再 `mv`）、`chmod 600`、
原文件自动备份为 `config.toml.bak.<时间戳>`。

### `opencode` → `~/.config/opencode/opencode.json`

**合并写入**，已有的 `plugin` / `mcp` / 其他 provider 全部保留。

未知网关的产物：

```json
{
  "$schema": "https://opencode.ai/config.json",
  "provider": {
    "gw-example-com": {
      "name": "gw.example.com",
      "npm": "@ai-sdk/openai-compatible",
      "options": {
        "baseURL": "https://gw.example.com/v1",
        "apiKey": "sk-xxxx"
      },
      "models": { "gpt-5.6": { "name": "gpt-5.6" } }
    }
  },
  "model": "gw-example-com/gpt-5.6"
}
```

`provider` id 会**自动识别**常见网关：

| base-url 含 | provider id | npm |
|---|---|---|
| `openrouter.ai` | `openrouter` | *(内置)* |
| `api.deepseek.com` | `deepseek` | `@ai-sdk/openai-compatible` |
| `api.openai.com` | `openai` | *(内置)* |
| `generativelanguage.googleapis.com` | `google` | *(内置)* |
| `open.bigmodel.cn` | `zhipuglm` | `@ai-sdk/openai-compatible` |
| 其他 | 由 host 推导，如 `my-custom-gw-io` | `@ai-sdk/openai-compatible` |

想手动指定：

```bash
./ai-cli-setup.sh opencode -y --base-url https://my.gw.io/v1 --api-key sk-x \
  --models a,b \
  --opencode-provider mygw \
  --opencode-provider-name "My Gateway" \
  --opencode-npm @ai-sdk/openai-compatible
```

---

## 3. 模型列表是怎么来的

```bash
./ai-cli-setup.sh all
```

1. 脚本请求 `<base-url>/v1/models`
   （如果 base-url 已以 `/v1` 结尾，就请求 `<base-url>/models`）
2. 用 `jq` → `python3` → `node` 里**第一个可用的**解析
3. 交互模式下把列表打印出来，回车 = 全部注册；非交互模式直接全用

拉不到就手动指定：

```bash
--models gpt-5.6,gpt-5.5,claude-sonnet-4-5
```

---

## 4. 完整参数表

| 参数 | 说明 |
|---|---|
| `-y, --yes` | 非交互；缺凭据直接报错 |
| `-i, --interactive` | 强制走上游向导 |
| `--delegate` | 不收集凭据，完全交给上游向导 |
| `-l, --lang en\|zh` | 输出与向导语言（默认按系统 locale） |
| `--base-url URL` | 接口地址 |
| `--api-key KEY` / `--token` | 密钥 |
| `--models a,b,c` | 注册的模型 id（pi / omo / opencode） |
| `--model ID` | 默认模型（claude / codex / grok / opencode） |
| `--grok-alias NAME` | Grok 本地模型别名（默认 `Steve`） |
| `--grok-search on\|off` | 开启服务端 Search Tool |
| `--opencode-provider ID` | OpenCode provider id |
| `--opencode-provider-name` | 显示名 |
| `--opencode-npm` | SDK 包名 |
| `--opencode-method official\|npm` | OpenCode 安装方式 |
| `--opencode-config FILE` | opencode.json 路径 |
| `--only a,b` | 只处理这些工具 |
| `--skip a,b` | 跳过这些工具 |
| `--skip-install` | 只改配置，不装/更新 CLI |
| `--ref REF` | 上游 git ref（默认 `main`） |
| `--pin` | 用已验证的固定提交（见 [VERSIONS.md](../VERSIONS.md)） |
| `--refresh` | 忽略缓存重新下载 |
| `--no-cache` | 不用也不写缓存 |
| `--fail-fast` | 第一个失败就停 |
| `--dry-run` | 只打印，不落盘 |
| `--` | 之后的参数原样透传给上游 |

---

## 5. 环境变量

除了命令行参数，也支持环境变量（适合 CI）：

```
AICLI_BASE_URL   AICLI_API_KEY   AICLI_MODELS   AICLI_MODEL   AICLI_LANG
AICLI_REF        AICLI_CACHE_DIR AICLI_RAW_HOST AICLI_OWNER
AICLI_OPENCODE_CONFIG   AICLI_OPENCODE_PROVIDER   AICLI_OPENCODE_METHOD
```

优先级：**命令行 > 环境变量 > 交互输入 > 默认值**。

内网镜像可以这样覆盖下载源：

```bash
AICLI_RAW_HOST=https://git.example.com/raw \
AICLI_JSD_HOST=https://cdn.example.com/gh \
AICLI_OWNER=my-mirror \
./ai-cli-setup.sh all
```

---

## 6. 缓存

上游脚本下载到 `~/.cache/ai-cli-setup/<repo>@<ref>/`：

```
~/.cache/ai-cli-setup/
├── pi-setup@main/
├── omo-setup@main/
├── claude-code-linux-installer@main/
├── deploy-codex@main/
└── GrokBuild@main/
```

- 仓库内 `upstream/` 有快照时**优先用快照**（离线可用，`list` 里显示 `local`）
- `--refresh` 强制重下；`--no-cache` 完全不碰缓存
- 想清空：`rm -rf ~/.cache/ai-cli-setup`

---

## 7. 备份与回滚

| 文件 | 备份位置 |
|---|---|
| `~/.grok/config.toml` | `config.toml.bak.<时间戳>` |
| `~/.config/opencode/opencode.json` | `opencode.json.bak.<时间戳>` |
| `~/.codex/*` | 上游自己管理，支持 `./ai-cli-setup.sh codex -- --restore` |
| `~/.pi/agent/models.json` | 上游写入 `.bak.<ISO时间戳>` |

手动回滚：

```bash
cp ~/.grok/config.toml.bak.20261010120000 ~/.grok/config.toml
```
