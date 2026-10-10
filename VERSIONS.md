# 上游版本锁定 / upstream version lock

`ai-cli-setup.sh --pin` 会使用下列提交，保证可复现安装。
默认（不加 `--pin`）跟随各仓库 `main` 分支。

生成时间：2026-10-10

| 工具 | 仓库 | 分支 | 提交 |
|---|---|---|---|
| pi | [zxfccmm4/pi-setup](https://github.com/zxfccmm4/pi-setup) | main | `caa0aaac6f1c07ae77e74210d97e814e78e065cd` |
| omo | [zxfccmm4/omo-setup](https://github.com/zxfccmm4/omo-setup) | main | `1e10043c8b0437d76cd565ea10cefcf5837f211e` |
| claude | [zxfccmm4/claude-code-linux-installer](https://github.com/zxfccmm4/claude-code-linux-installer) | main | `7b944386a3e43d2c364e2abb202385a688476789` |
| codex | [zxfccmm4/deploy-codex](https://github.com/zxfccmm4/deploy-codex) | main | `3fd91ce6e364720383edbff3899e6578b4835384` |
| grok | [zxfccmm4/GrokBuild](https://github.com/zxfccmm4/GrokBuild) | main | `287232842a9ad989a2f8050a935be881fe4f6d4a` |

本地 `upstream/` 目录内是同一批文件的快照（离线可用）。
删除 `upstream/` 后，脚本会自动从 raw.githubusercontent.com 下载
（失败时回退 cdn.jsdelivr.net）。
