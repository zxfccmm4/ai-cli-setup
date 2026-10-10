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

| ID | 装什么 | 上游 | 配置文件 |
|---|---|---|---|
| `pi` | Pi | [pi-setup](https://github.com/zxfccmm4/pi-setup) | `~/.pi/agent/{models.json,settings.json}` |
| `omo` | OmO | [omo-setup](https://github.com/zxfccmm4/omo-setup) | `~/.omo/agent/*`、`~/.omo/omo.jsonc` |
| `claude` | Claude Code | [claude-code-linux-installer](https://github.com/zxfccmm4/claude-code-linux-installer) | shell 配置 / `~/.claude/settings.json` |
| `codex` | Codex CLI | [deploy-codex](https://github.com/zxfccmm4/deploy-codex) | `~/.codex/{config.toml,auth.json}` |
| `grok` | Grok Build | [GrokBuild](https://github.com/zxfccmm4/GrokBuild) | `~/.grok/config.toml` |
| `opencode` | OpenCode | *(内置实现)* | `~/.config/opencode/opencode.json` |

## 三个核心概念

1. **编排，不重写**：前 5 个工具直接调用上游脚本，参数与体验和单独用完全一致。
   本脚本只负责「选工具 → 问一次凭据 → 翻译成各家变量 → 依次执行 → 汇总」。
2. **凭据只问一次**：`--base-url` / `--api-key` 统一输入，脚本映射成
   `PISETUP_*` / `OMO_*` / `CLAUDE_*` / `CODEX_*`，或直接写进 Grok / OpenCode 的配置文件。
3. **可复现**：`--pin` 锁定已验证的上游提交（见 [VERSIONS.md](../VERSIONS.md)），
   `--dry-run` 只打印不落盘。
