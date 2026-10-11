# 配置详解

这一页讲清楚：**你给的参数，最后变成了什么。**

---

## 1. 每个 agent 写什么文件

| Agent | 文件 | 格式 | 默认模型位置 |
|---|---|---|---|
| `pi` | `~/.pi/agent/{models,settings}.json` | JSON | `settings.json: defaultModel` |
| `omo` | `~/.omo/agent/{models,settings}.json` | JSON | `settings.json: defaultModel` |
| `omp` | `~/.omp/agent/{models.yml,config.yml}` | YAML | `config.yml: modelRoles.default` |
| `claude` | `~/.claude/settings.json` | JSON | `env.ANTHROPIC_MODEL` |
| `codex` | `~/.codex/{config.toml,auth.json}` | TOML / JSON | `model` |
| `grok` | `~/.grok/config.toml` | TOML | `[models].default`（别名） |
| `opencode` | `~/.config/opencode/opencode.json` | JSON | `model` |

全部由本脚本直接生成，**不调用任何上游配置脚本**。写入前会备份为
`<文件>.bak.<时间戳>`，写入后 `chmod 600`。

---

## 2. 参数 → 各 agent 的落点

| 统一参数 | pi / omo | omp | claude | codex | grok | opencode |
|---|---|---|---|---|---|---|
| `--base-url` | `providers.<host>.baseUrl` | `providers.<host>.baseUrl` | `env.ANTHROPIC_BASE_URL`（剥掉尾部 `/v1`） | `model_providers.OpenAI.base_url`（剥掉 `/v1`） | `[model.<alias>].base_url` | `<provider>.options.baseURL` |
| `--api-key` | `providers.<host>.apiKey` | `providers.<host>.apiKey` | `env.ANTHROPIC_AUTH_TOKEN` | `auth.json: OPENAI_API_KEY` | `[model.<alias>].api_key` | `options.apiKey` / `{env:…}`（V2） |
| `--models a,b` | `providers.<host>.models[]` | `providers.<host>.models[]` | — | — | — | `<provider>.models{}` |
| `--model ID` | `settings.json: defaultModel` | `config.yml: modelRoles.default` | `env.ANTHROPIC_MODEL` | `model` / `review_model` | `[models].default` 别名 | `model: <provider>/<ID>` |
| `--lang en\|zh` | 仅界面语言 | 仅界面语言 | 仅界面语言 | 仅界面语言 | 仅界面语言 | 仅界面语言 |

`--models` 缺省时会请求 `<base-url>/v1/models` 自动拉取（见第 3 节）；
`--model` 缺省时取 `--models` 的第一个。

---

## 3. 各 agent 的产物样例

### `pi` / `omo`

```json
{
  "providers": {
    "gw-example-com": {
      "baseUrl": "https://gw.example.com/v1",
      "api": "openai-completions",
      "apiKey": "sk-xxxx",
      "models": [{ "id": "gpt-5.6", "name": "gpt-5.6" }]
    }
  }
}
```

`settings.json` 里 `defaultProvider` + `defaultModel`（纯模型 id，不带 provider 前缀）。

### `omp` → `~/.omp/agent/models.yml`

```yaml
providers:
  gw-example-com:
    baseUrl: "https://gw.example.com/v1"
    api: openai-completions
    apiKey: "sk-xxxx"
    models:
      - id: "gpt-5.6"
        name: "gpt-5.6"
```

`~/.omp/agent/config.yml` 只改 `modelRoles.default`，其它设置（`theme`、
`setupVersion`、`smol` / `slow` 角色等）原样保留：

```yaml
modelRoles:
  default: gw-example-com/gpt-5.6
```

> **注意**：omp 的 `models.yml` **不做环境变量插值**（`apiKey: ${VAR}` 会被原样发送），
> 所以密钥是明文写入的，脚本强制 `600`。omp 也没有 `{env:}` 之类的引用语法。
>
> omp 已安装时，脚本用 `omp config set modelRoles`（JSON 合并）来改默认模型，
> 能保留 `smol`/`slow` 等其它角色并通过 schema 校验；omp 不可用时退回文本级替换，
> 同样只动 `default` 那一行。

### `claude` → `~/.claude/settings.json`

```json
{
  "env": {
    "ANTHROPIC_BASE_URL": "https://gw.example.com",
    "ANTHROPIC_AUTH_TOKEN": "sk-xxxx",
    "ANTHROPIC_MODEL": "gpt-5.6"
  }
}
```

Claude Code 自己在 base 后面拼 `/v1/messages`，所以脚本**必须**写不带 `/v1` 的根地址。
已有文件里的其它键（`permissions`、`hooks` …）会被保留。

### `codex` → `~/.codex/config.toml` + `auth.json`

```toml
model_provider = "OpenAI"
model = "gpt-5.6"
review_model = "gpt-5.6"

[model_providers.OpenAI]
name = "OpenAI"
base_url = "https://gw.example.com"
wire_api = "responses"
requires_openai_auth = true
```

`wire_api` 可用 `CODEX_WIRE_API=chat` 切换（部分网关只支持 chat completions）。

### `grok` → `~/.grok/config.toml`

```toml
[cli]
installer = "internal"

[models]
default = "main"

[model.main]
model = "grok-4.7"
base_url = "https://gw.example.com/v1"
api_key = "sk-xxxx"
context_window = 500000
supports_reasoning_effort = true
reasoning_efforts = ["low", "medium", "high"]

[features]
telemetry = false
feedback = false
```

别名可用 `--grok-alias` / `GROK_ALIAS` 改，上下文窗口用 `GROK_CONTEXT_WINDOW`。

### `opencode` → `~/.config/opencode/opencode.json`

**合并写入**，已有的 `plugin` / `mcp` / 其他 provider 全部保留。
格式分两代，脚本自动选择：

**V1**（`provider` + `options`，密钥直写）：

```json
{
  "$schema": "https://opencode.ai/config.json",
  "provider": {
    "gw-example-com": {
      "name": "gw.example.com",
      "npm": "@ai-sdk/openai-compatible",
      "options": { "baseURL": "https://gw.example.com/v1", "apiKey": "sk-xxxx" },
      "models": { "gpt-5.6": { "name": "gpt-5.6" } }
    }
  },
  "model": "gw-example-com/gpt-5.6"
}
```

**V2**（`providers` + `settings` + `package`，密钥用 `{env:}` 引用）：

```json
{
  "$schema": "https://opencode.ai/config.json",
  "providers": {
    "gw-example-com": {
      "name": "gw.example.com",
      "package": "aisdk:@ai-sdk/openai-compatible",
      "settings": {
        "baseURL": "https://gw.example.com/v1",
        "apiKey": "{env:AICLI_GW_EXAMPLE_COM_API_KEY}"
      },
      "models": { "gpt-5.6": { "name": "gpt-5.6" } }
    }
  },
  "model": "gw-example-com/gpt-5.6"
}
```

V2 下真实密钥写进 shell 配置（`export AICLI_<PROVIDER>_API_KEY='…'`），
`opencode.json` 里只有引用——重跑会**原地更新**那一行，不会堆叠。

**V1 / V2 的选择顺序**：

1. `AICLI_OPENCODE_V2=1` → V2（`=0` → V1）
2. 已安装的 `opencode --version` 主版本 ≥ 2 → V2
3. 现有 `opencode.json` 里已有 `providers` 键 → V2
4. 否则 V1

> `--dry-run` 下不执行 `opencode --version`（该命令会自建 cache/state/log 目录），
> 只按第 3 条判断。

**provider id 自动识别**：

| base-url 含 | provider id | package |
|---|---|---|
| `openrouter.ai` | `openrouter` | *(内置)* |
| `api.deepseek.com` | `deepseek` | `@ai-sdk/openai-compatible` |
| `api.openai.com` | `openai` | *(内置)* |
| `generativelanguage.googleapis.com` | `google` | *(内置)* |
| `open.bigmodel.cn` | `zhipuglm` | `@ai-sdk/openai-compatible` |
| 其他 | 由 host 推导，如 `gw-example-com` | `@ai-sdk/openai-compatible` |

---

## 4. 模型列表是怎么来的

```bash
./ai-cli-setup.sh all
```

1. 请求 `<base-url>/models`（base-url 已以 `/v1` 结尾）或 `<base-url>/v1/models`
2. 带 `Authorization: Bearer <api-key>`
3. 依次尝试 `jq` → `node` → `python3` 解析
4. 交互模式下打印列表，回车 = 全部注册；非交互模式直接全用

拉不到就手动指定：`--models gpt-5.6,gpt-5.5,claude-sonnet-4-5`。

---

## 5. 完整参数表

| 参数 | 说明 |
|---|---|
| `-y, --yes` | 非交互；缺凭据直接报错 |
| `-l, --lang en\|zh` | 界面语言（默认按系统 locale） |
| `--base-url URL` | 接口地址 |
| `--api-key KEY` | 密钥（交互输入时掩码显示） |
| `--models a,b,c` | 注册的模型 id（pi / omo / omp / opencode） |
| `--model ID` | 默认模型（claude / codex / grok / omp / opencode） |
| `--grok-alias NAME` | Grok 本地模型别名（默认 `main`） |
| `--skip-install` | 只改配置，不装/更新 CLI |
| `--dry-run` | 只打印计划，零落盘 |
| `--fail-fast` | 第一个失败就停 |
| `--assume-tty` | 把 stdin 当交互输入（容器 / CI） |
| `list` / `doctor` / `help` | 子命令 |

位置参数：`pi`、`omo`、`omp`、`claude`、`codex`、`grok`、`opencode`、
`all`，也可用逗号组合（`pi,opencode`）。

---

## 6. 环境变量

```
AICLI_BASE_URL   AICLI_API_KEY   AICLI_MODELS   AICLI_MODEL   AICLI_LANG
AICLI_ASSUME_TTY AICLI_OPENCODE_V2
GROK_ALIAS       GROK_CONTEXT_WINDOW            CODEX_WIRE_API
```

优先级：**命令行 > 环境变量 > 交互输入 > 默认值**。

---

## 7. 备份与回滚

| 文件 | 备份位置 |
|---|---|
| `~/.pi/agent/{models,settings}.json` | 同目录 `.bak.<时间戳>` |
| `~/.omo/agent/{models,settings}.json` | 同目录 `.bak.<时间戳>` |
| `~/.omp/agent/{models.yml,config.yml}` | 同目录 `.bak.<时间戳>` |
| `~/.claude/settings.json` | 同目录 `.bak.<时间戳>` |
| `~/.codex/{config.toml,auth.json}` | 同目录 `.bak.<时间戳>` |
| `~/.grok/config.toml` | 同目录 `.bak.<时间戳>` |
| `~/.config/opencode/opencode.json` | 同目录 `.bak.<时间戳>` |

手动回滚：

```bash
cp ~/.grok/config.toml.bak.20261010120000 ~/.grok/config.toml
```

`--dry-run` 不产生任何备份，也不创建目录。
