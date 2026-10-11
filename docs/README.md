# 文档 / Documentation

`ai-cli-setup` 的详细中文文档。README 是速查表，这里讲清楚「为什么」和「怎么做」。

| 文档 | 内容 | 适合 |
|---|---|---|
| [quickstart.md](./quickstart.md) | 5 分钟装完第一个工具 | 第一次用 |
| [configuration.md](./configuration.md) | 每个工具写什么文件、参数怎么映射 | 想搞清楚配置细节 |
| [troubleshooting.md](./troubleshooting.md) | 报错、网络、权限、回滚 | 出问题时 |
| [development.md](./development.md) | 本地开发、测试、CI、发版 | 想改代码或发版 |

## 30 秒速览

```bash
# 交互式（推荐第一次）
./ai-cli-setup.sh

# 全部装，凭据只问一次
./ai-cli-setup.sh all

# 完全非交互
./ai-cli-setup.sh all -y \
  --base-url https://gw.example.com/v1 \
  --api-key sk-xxxx \
  --models gpt-5.6,gpt-5.5
```

## 支持的工具

| ID | 装什么 | 官方渠道 | 配置文件 |
|---|---|---|---|
| `pi` | Pi | [pi.dev](https://pi.dev) / npm `@earendil-works/pi-coding-agent` | `~/.pi/agent/{models,settings}.json` |
| `omo` | OmO | [get.omo.dev](https://omo.dev) | `~/.omo/agent/{models,settings}.json` |
| `omp` | OMP | [omp.sh](https://omp.sh)（回退 bun / npm） | `~/.omp/agent/{models.yml,config.yml}` |
| `claude` | Claude Code | [claude.ai](https://claude.com/product/claude-code)（仅 Linux/WSL 安装） | `~/.claude/settings.json` |
| `codex` | Codex CLI | npm `@openai/codex` | `~/.codex/{config.toml,auth.json}` |
| `grok` | Grok Build | [x.ai/cli](https://x.ai/cli) | `~/.grok/config.toml` |
| `opencode` | OpenCode | [opencode.ai](https://opencode.ai) | `~/.config/opencode/opencode.json` |

## 三个核心概念

1. **只走官方渠道**：各 agent 都用官方 installer 或官方 npm 包安装，
   本脚本不下载也不包装任何第三方安装脚本。
2. **凭据只问一次**：`--base-url` / `--api-key` 统一输入，脚本翻译成
   各家的原生配置格式（JSON / TOML / YAML），一次写入全部所选 agent。
3. **可预览、可回滚**：`--dry-run` 只打印计划且零落盘；写入前自动生成
   带时间戳的备份，合并写入不丢你已有的其它配置。
