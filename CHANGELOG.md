# Changelog

本项目所有值得注意的改动都记录在此文件。
格式参考 [Keep a Changelog](https://keepachangelog.com/zh-CN/1.1.0/)，版本号遵循 [语义化版本](https://semver.org/lang/zh-CN/)。

All notable changes to this project are documented here.
Format based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/), versioning follows [Semantic Versioning](https://semver.org/).

## [v1.0.0] - 2026-10-10

### ✨ Features

- 新增 Release 自动化与 CHANGELOG 生成器 ([`33a2017`](https://github.com/zxfccmm4/ai-cli-setup/commit/33a2017edb3c958d82eef4c9c16688e65983ef1f))
- 新增 opencode 支持 + GitHub Actions CI ([`9329890`](https://github.com/zxfccmm4/ai-cli-setup/commit/93298903925d279b8ddbca725d373d5524cc2ebd))
- 统一 zxfccmm4 系列 AI CLI 安装脚本 ([`7754a52`](https://github.com/zxfccmm4/ai-cli-setup/commit/7754a52a5ff9ef35ec67d15a4c99da4a1236c58e))

### 🔧 CI

- CHANGELOG 检查改用完整历史，过期改为告警而非失败 ([`16a81d5`](https://github.com/zxfccmm4/ai-cli-setup/commit/16a81d523519d559f36d9a3117368bab37e83f22))
- 升级 actions/checkout 与 setup-node 到 v7（消除 Node 20 弃用告警） ([`7ee737f`](https://github.com/zxfccmm4/ai-cli-setup/commit/7ee737fa6e683420d70c4584a66176af013792a2))
- 修复隔离 HOME 测试失败（runner 预置 XDG_CONFIG_HOME） ([`ca61e58`](https://github.com/zxfccmm4/ai-cli-setup/commit/ca61e58c8a54e38a284fa52cfe038361dfb08243))


## [Unreleased]

### ✨ Features

- 运行先选语言（英文/中文），再选 agent（单选/多选/全部） ([`eb9646e`](https://github.com/zxfccmm4/ai-cli-setup/commit/eb9646e6aaf469266cf4a0382186a78e947aaba4))

### 🐛 Bug Fixes

- 拉取模型列表时带上 API key（Bearer） ([`becd51e`](https://github.com/zxfccmm4/ai-cli-setup/commit/becd51e7f83b800b258ab54812d19a21f7999f2a))
- 修复 bash 3.2 下 $var 紧跟中文导致的 unbound variable ([`a394b98`](https://github.com/zxfccmm4/ai-cli-setup/commit/a394b981fe78ddfe6d810cbb712f58fce7d28671))

### 📝 Documentation

- 重构 README ([`d4ad8be`](https://github.com/zxfccmm4/ai-cli-setup/commit/d4ad8be4cd5b25ed06337a1332ff3b50e14256a5))
- 补充 Release 产物说明（chmod +x 与独立使用） ([`611e6d6`](https://github.com/zxfccmm4/ai-cli-setup/commit/611e6d61ba1a914f3c401ec7b94ded8a2ff0af68))

### 🔧 CI

- 把多字节变量检查抽成 scripts/check-multibyte-vars.py ([`0192033`](https://github.com/zxfccmm4/ai-cli-setup/commit/0192033c19b83ef2d360d4efce4a834edf65d476))


