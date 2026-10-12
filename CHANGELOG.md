# Changelog

本项目所有值得注意的改动都记录在此文件。
格式参考 [Keep a Changelog](https://keepachangelog.com/zh-CN/1.1.0/)，版本号遵循 [语义化版本](https://semver.org/lang/zh-CN/)。

All notable changes to this project are documented here.
Format based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/), versioning follows [Semantic Versioning](https://semver.org/).

## [v2.1.0] - 2026-10-12

### ✨ Features

- 新增 OMP（@oh-my-pi/pi-coding-agent）安装与配置 ([`4f527b4`](https://github.com/zxfccmm4/ai-cli-setup/commit/4f527b44a28cb37966d87bdc3fb20d12012343cd))
- 优化终端交互体验、修复 provider 映射与跨平台兼容性并美化 README ([`0b92578`](https://github.com/zxfccmm4/ai-cli-setup/commit/0b9257837b976574e2b4c828f42f7bd88a57b09f))
- opencode 支持 V2 配置格式（providers/settings/package + env 凭据引用） ([`b518fb8`](https://github.com/zxfccmm4/ai-cli-setup/commit/b518fb87b0b3b0bcc81ea67dce1981d28dd606f0))
- v2.0 全自研重写——不再包装上游脚本 ([`c6a9852`](https://github.com/zxfccmm4/ai-cli-setup/commit/c6a9852219ba6c741b5c08397cd52bca7180b904))
- API key 改为显式掩码输入，实时显示前3+星号+后3 ([`1eb53c6`](https://github.com/zxfccmm4/ai-cli-setup/commit/1eb53c6e02d82182acbc8da1a04ab9ccfcf31768))
- 运行先选语言（英文/中文），再选 agent（单选/多选/全部） ([`eb9646e`](https://github.com/zxfccmm4/ai-cli-setup/commit/eb9646e6aaf469266cf4a0382186a78e947aaba4))

### 🐛 Bug Fixes

- 失败隔离用例改为与系统无关的断言 ([`5405ce4`](https://github.com/zxfccmm4/ai-cli-setup/commit/5405ce473329ced461f4b6b25ad52c454fb6a660))
- 掩码输入不再截断重定向日志（Linux 上 /dev/stderr 的 O_TRUNC 陷阱） ([`e5c4bb4`](https://github.com/zxfccmm4/ai-cli-setup/commit/e5c4bb4f964a3779ec75ec3016b3691c85eaba03))
- 修复 shellcheck SC2120、omp 角色标量引号不一致，并让交互用例失败时打印输出 ([`0adf1b2`](https://github.com/zxfccmm4/ai-cli-setup/commit/0adf1b28ea569a10f12b42c7611fd5db1dda5724))
- 安装失败如实上报、依赖缺失不再中断全局、dry-run 零落盘、OpenCode V2 检测与凭据导出 ([`fccaee0`](https://github.com/zxfccmm4/ai-cli-setup/commit/fccaee022f08bfc101af0b36c7b224ca6e0fde41))
- 修复 iStoreOS/OpenWrt 上 OmO 配置失败、命令找不到、依赖 Node 的 agent 应跳过 ([`3e00c96`](https://github.com/zxfccmm4/ai-cli-setup/commit/3e00c96d4c54ccf65b19ddf2c28ccf8116afd002))
- 默认模型必填 + set -e 函数返回值陷阱 ([`02326a6`](https://github.com/zxfccmm4/ai-cli-setup/commit/02326a687f0d7868eb0ecc897fe72e1efa2190e0))
- OpenWrt/musl 三连修——node 拒装、claude 纯 bash 配置、PATH 写 profile.d ([`f49d7eb`](https://github.com/zxfccmm4/ai-cli-setup/commit/f49d7eba2f4f361c049bcb0aa2d324a0434b026b))
- musl 系统（OpenWrt/iStoreOS）安装 opencode 官方 musl 变体 ([`cd3feb3`](https://github.com/zxfccmm4/ai-cli-setup/commit/cd3feb34f9c73d8c25e417f1b23a5168ddcfdb44))
- BusyBox tr 不认字符类导致模型名损坏 + PATH 提示增强 ([`ad35eb6`](https://github.com/zxfccmm4/ai-cli-setup/commit/ad35eb62ddfdf475e87a93dd6346cefb4b9c5f08))
- 兼容无 node/npm/paste 的精简系统（OpenWrt/BusyBox） ([`82cbe80`](https://github.com/zxfccmm4/ai-cli-setup/commit/82cbe8013483299af05f222836bb38927a55533c))
- 安装后清 bash 命令缓存并打印二进制真实位置 ([`24b199f`](https://github.com/zxfccmm4/ai-cli-setup/commit/24b199f105ed6cd91ae1909425c6dab8b2dea949))
- Claude Code 的 ANTHROPIC_BASE_URL 剥掉尾部 /v1 ([`ba33bef`](https://github.com/zxfccmm4/ai-cli-setup/commit/ba33beff7bdcc5c0ed49640cebd6cf6a36554cc1))
- pi 安装改为 npm 优先——官方 install.sh 会问 Start pi now? 且默认 Y ([`a54416b`](https://github.com/zxfccmm4/ai-cli-setup/commit/a54416bea9f692a0a403c77d27d2f5ba45c80cca))
- 凭据齐全时 Codex 强制非交互，非 sk- key 不再卡确认提问 ([`9c63445`](https://github.com/zxfccmm4/ai-cli-setup/commit/9c63445ddf70a7db42bede3c59121e92a8d4db57))
- 掩码输入改用 stty -echo，消除快速输入时的明文闪现 ([`45b9031`](https://github.com/zxfccmm4/ai-cli-setup/commit/45b9031c08ce1b7563426ffa191b7df947a419b4))
- 管道模式下 have_tty 的 exec 泄漏把 stderr 永久吞进 /dev/null ([`018570e`](https://github.com/zxfccmm4/ai-cli-setup/commit/018570e527974d7452dda30497e0f54ee4a4b76c))
- 模型列表过多时多行展示、默认值截断显示 ([`cdc51be`](https://github.com/zxfccmm4/ai-cli-setup/commit/cdc51bea20e277aff206567d9d491212b28710cb))
- 拉取模型列表时带上 API key（Bearer） ([`becd51e`](https://github.com/zxfccmm4/ai-cli-setup/commit/becd51e7f83b800b258ab54812d19a21f7999f2a))
- 修复 bash 3.2 下 $var 紧跟中文导致的 unbound variable ([`a394b98`](https://github.com/zxfccmm4/ai-cli-setup/commit/a394b981fe78ddfe6d810cbb712f58fce7d28671))

### ♻️ Refactoring

- 删除 upstream/ 快照——脚本改为全自研安装，不再包装上游仓库 ([`e86aece`](https://github.com/zxfccmm4/ai-cli-setup/commit/e86aece16d86f5d06596ff2906d24597b5d929a5))

### 📝 Documentation

- 同步 CHANGELOG 与 V2 凭据提示文案 ([`4d8d66a`](https://github.com/zxfccmm4/ai-cli-setup/commit/4d8d66a5da058a9ca60a2d6f1389f9897a389261))
- 文档与 CI 对齐 2.1 现状，删除 v1 残留 ([`9cfef15`](https://github.com/zxfccmm4/ai-cli-setup/commit/9cfef15f5f69a8cfc554f50a6397ef7c1aed819c))
- README 改版为介绍版 ([`0910b27`](https://github.com/zxfccmm4/ai-cli-setup/commit/0910b27cfd65e7d99b626333b7aeda5ad41313d8))
- README 二次优化 ([`a8cd73c`](https://github.com/zxfccmm4/ai-cli-setup/commit/a8cd73cea1eba04891b9c4b0b0c8607e91726277))
- 重构 README ([`d4ad8be`](https://github.com/zxfccmm4/ai-cli-setup/commit/d4ad8be4cd5b25ed06337a1332ff3b50e14256a5))
- 补充 Release 产物说明（chmod +x 与独立使用） ([`611e6d6`](https://github.com/zxfccmm4/ai-cli-setup/commit/611e6d61ba1a914f3c401ec7b94ded8a2ff0af68))

### 🔧 CI

- 把多字节变量检查抽成 scripts/check-multibyte-vars.py ([`0192033`](https://github.com/zxfccmm4/ai-cli-setup/commit/0192033c19b83ef2d360d4efce4a834edf65d476))


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

- 新增滚动预发布渠道，每次提交自动更新 Release ([`4f2a054`](https://github.com/zxfccmm4/ai-cli-setup/commit/4f2a05472a70d8d7495ddd39c9aa2e41f90e8fb7))

### 🐛 Bug Fixes

- changelog.sh 只认版本 tag，避免移动 tag 破坏版本节 ([`7ba60bc`](https://github.com/zxfccmm4/ai-cli-setup/commit/7ba60bc265e346ead7343da8c012f0f50e491596))
- Pi 安装不再劫持终端，无 Homebrew 的 macOS 也能装 Node ([`86d9774`](https://github.com/zxfccmm4/ai-cli-setup/commit/86d977438d9042d40b6c578257c17680be748b9a))

### 🔨 Chores

- bump VERSION 到 2.1.1 ([`4e41efc`](https://github.com/zxfccmm4/ai-cli-setup/commit/4e41efc8ea91e2c4b47985b0983fa8ec29ade7d3))


