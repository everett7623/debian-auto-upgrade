# 🚀 Debian Auto Upgrade Tool

> 专为 Debian 系统设计的智能逐级升级工具，支持 VPS 环境优化、自动错误修复与保守升级策略

[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](https://opensource.org/licenses/MIT)
[![GitHub release](https://img.shields.io/github/release/everett7623/debian-auto-upgrade.svg)](https://github.com/everett7623/debian-auto-upgrade/releases)
[![Debian](https://img.shields.io/badge/Debian-8%2B-red.svg)](https://www.debian.org/)
[![Bash](https://img.shields.io/badge/Language-Bash-green.svg)](https://www.gnu.org/software/bash/)
[![Version](https://img.shields.io/badge/Version-3.0-brightgreen.svg)](https://github.com/everett7623/debian-auto-upgrade/releases)

专为 Debian 系统打造的自动化升级脚本，支持从旧版本安全逐级升级到最新稳定版本。针对 VPS 环境深度优化，具备完善的错误恢复与容错能力。

## ✨ 功能特性

- 🔄 **逐级安全升级** — 从 Debian 8 逐步升级到最新版本，避免跨版本风险
- 🛡️ **智能版本管控** — 默认阻止意外升级到不稳定版本，`--stable-only` 模式保障生产安全
- 🌍 **国内镜像支持** — 一键切换阿里云 / 清华 / 中科大镜像源，国内 VPS 推荐使用
- 🔧 **APT 源自动清理** — 升级前自动禁用旧版 backports 和第三方源，解决 404 报错
- 💾 **配置完整备份** — 升级前自动备份网络配置、APT 源等关键文件
- 🖥️ **GRUB 智能修复** — UEFI/BIOS 双模式检测，NVMe / virtio / Xen 磁盘全兼容
- 📊 **彩色日志输出** — 带时间戳的分级日志，`--debug` 模式输出完整诊断信息
- 🔍 **升级前后验证** — 自动校验升级结果，失败时触发错误恢复流程
- ⚠️ **风险分级确认** — 稳定版一键确认，测试版强制输入 `YES` 二次确认

## 🎯 支持的升级路径

| 源版本 | 目标版本 | 状态 | 安全性 | 说明 |
|---|---|---|---|---|
| Debian 8 (Jessie) | Debian 9 (Stretch) | ✅ 支持 | 🔒 安全 | 旧版升级 |
| Debian 9 (Stretch) | Debian 10 (Buster) | ✅ 支持 | 🔒 安全 | 旧版升级 |
| Debian 10 (Buster) | Debian 11 (Bullseye) | ✅ 支持 | 🔒 安全 | 稳定升级 |
| Debian 11 (Bullseye) | Debian 12 (Bookworm) | ✅ 支持 | 🔒 安全 | 当前推荐 |
| Debian 12 (Bookworm) | Debian 13 (Trixie) | ⚠️ 测试版 | 🧪 谨慎 | 需明确确认，不建议生产环境 |
| Debian 13 (Trixie) | Debian 14 (Forky) | ⚠️ 测试版 | 🧪 谨慎 | 需明确确认，不建议生产环境 |

> **建议：** 生产系统请保持 Debian 12 (Bookworm)，这是当前稳定版。

## 🚀 快速开始

### 一键安装运行

```bash
wget -O debian_upgrade.sh https://raw.githubusercontent.com/everett7623/debian-auto-upgrade/main/debian_upgrade.sh \
  && chmod +x debian_upgrade.sh \
  && sudo ./debian_upgrade.sh
```

### 基本用法

```bash
# 检查当前版本与可用升级
sudo ./debian_upgrade.sh --check

# 仅升级到稳定版（推荐）
sudo ./debian_upgrade.sh --stable-only

# 使用国内镜像源升级（国内 VPS 推荐）
sudo ./debian_upgrade.sh --mirror cn

# 查看当前版本
sudo ./debian_upgrade.sh --version

# 查看帮助
sudo ./debian_upgrade.sh --help
```

## 📖 命令参数

| 参数 | 说明 |
|------|------|
| `-h, --help` | 显示帮助信息 |
| `-v, --version` | 显示当前 Debian 版本 |
| `-c, --check` | 检查可用升级及系统状态 |
| `-d, --debug` | 启用调试模式，输出详细诊断信息 |
| `--fix-only` | 仅修复系统问题，不执行升级 |
| `--fix-grub` | 专项修复 GRUB 引导问题 |
| `--force` | 跳过所有确认提示（慎用） |
| `--stable-only` | 仅升级到稳定版（默认，推荐） |
| `--allow-testing` | 允许升级到测试版 |
| `--mirror <cn\|tuna\|ustc>` | 使用指定国内镜像源 |

## 💡 使用示例

### 生产服务器（推荐）

```bash
# 检查状态，不执行升级
sudo ./debian_upgrade.sh --check

# 安全升级到下一稳定版
sudo ./debian_upgrade.sh --stable-only

# 国内服务器使用阿里云源
sudo ./debian_upgrade.sh --stable-only --mirror cn
```

### 开发 / 测试环境

```bash
# 允许升级到测试版（需手动输入 YES 确认）
sudo ./debian_upgrade.sh --allow-testing

# 自动化场景强制升级（极度谨慎）
sudo ./debian_upgrade.sh --force --stable-only

# 调试模式排查问题
sudo ./debian_upgrade.sh --debug
```

### 系统修复

```bash
# 修复 APT 锁、依赖冲突、旧内核
sudo ./debian_upgrade.sh --fix-only

# 专门修复 GRUB 引导（重启失败时使用）
sudo ./debian_upgrade.sh --fix-grub
```

## 🌍 国内镜像源

通过 `--mirror` 参数一键切换，显著提升国内 VPS 下载速度：

| 参数值 | 镜像源 | 适用场景 |
|--------|--------|----------|
| `cn` | 阿里云 mirrors.aliyun.com | 国内通用，速度最快 |
| `tuna` | 清华大学 mirrors.tuna.tsinghua.edu.cn | 教育网用户 |
| `ustc` | 中科大 mirrors.ustc.edu.cn | 教育网备选 |
| _(不填)_ | Debian 官方 deb.debian.org | 境外服务器 |

## 🔧 APT 源自动清理（v3.0 新增）

升级前脚本会自动处理以下问题，解决截图中常见的 **404 报错**：

- 自动备份并禁用 `/etc/apt/sources.list.d/` 下的旧版 backports 源
- 注释掉 `sources.list` 中遗留的 backports 行
- `apt-get update` 失败时二次兜底：禁用所有第三方源后重试
- 写入新版 `sources.list` 时自动适配各版本格式差异（Debian 11 的安全源格式、Debian 12 的 `non-free-firmware`）

## 📦 升级策略

### 三阶段升级流程

1. **最小升级** (`apt upgrade`) — 仅升级不涉及包增删的安全更新
2. **完整升级** (`apt dist-upgrade`) — 执行完整发行版升级
3. **升级后修复** — 重建 initramfs、修复 GRUB、重启网络服务

### 自动备份内容

- APT 源配置（`sources.list` + `sources.list.d/`）
- 网络接口配置（`/etc/network/interfaces`、systemd-networkd）
- 升级前 IP 地址与路由表快照

## 💻 系统要求

### 最低要求

- Debian 8 或更高版本
- 根分区可用空间 ≥ 2GB
- 可用内存 ≥ 256MB
- 稳定的互联网连接

### 生产环境建议

- 根分区可用空间 ≥ 4GB
- `/boot` 分区可用空间 ≥ 200MB（不足时自动清理旧内核）
- 可用内存 ≥ 1GB
- 具备 sudo 权限的用户账户

## ⚠️ 重要安全提示

### 升级前必做

- 📸 创建 VPS 快照（如使用云服务器）
- 💾 备份重要业务数据
- 📝 记录当前网络配置（IP、网关、DNS）
- 🔑 确保 VNC / 控制台访问可用（SSH 升级期间可能中断）

### Debian 12 用户须知

- ✅ 当前为最新稳定版，**建议保持不升级**
- ⚠️ 升级到 Debian 13 即进入 testing 分支，存在不稳定风险
- 🛡️ 使用 `--stable-only`（默认）可防止误升级到测试版
- 💡 测试版升级需手动输入 `YES` 进行二次确认

## 🔒 确认机制

| 升级类型 | 确认方式 |
|----------|----------|
| 稳定版 → 稳定版 | `[y/N]` 单次确认 |
| 稳定版 → 测试版 | 需手动输入 `YES`（大写）并阅读风险说明 |
| `--stable-only` 模式 | 不提供测试版升级选项 |
| `--force` 模式 | 跳过所有确认（极度谨慎） |

## 🐛 常见问题

### ❓ apt-get update 报 404 错误

这是最常见的问题，原因是旧版 backports 或第三方源在升级后失效。v3.0 已自动处理，若仍出现：

```bash
# 手动禁用所有第三方源后重试
sudo mv /etc/apt/sources.list.d/ /etc/apt/sources.list.d.bak/
sudo apt-get update
```

### ❓ APT 锁定错误

```bash
sudo ./debian_upgrade.sh --fix-only
```

### ❓ 重启后系统无法引导

```bash
# 进入救援模式 / Live CD，执行：
grub-install /dev/sdX
update-grub

# 或使用脚本修复（系统能启动时）：
sudo ./debian_upgrade.sh --fix-grub
```

### ❓ 包依赖冲突

脚本会自动尝试修复依赖。若问题持续：

```bash
sudo apt --fix-broken install
sudo dpkg --configure -a
```

### ❓ 升级后网络断开

```bash
# 通过 VPS 控制台登录后执行：
ip addr show
systemctl restart networking
# 或恢复备份配置（备份路径见升级日志）
```

## 📄 问题反馈

提交 Issue 时请附上以下信息：

- 当前系统版本：`cat /etc/os-release`
- 错误日志：使用 `--debug` 参数重新运行并复制输出
- 系统环境：物理机 / KVM / OpenVZ / 云厂商
- 网络环境：是否使用代理 / 防火墙

## 🤝 参与贡献

欢迎提交 Issue 和 Pull Request！

### 开发流程

1. Fork 本仓库
2. 创建功能分支：`git checkout -b feature/amazing-feature`
3. 提交变更：`git commit -m 'Add amazing feature'`
4. 推送分支：`git push origin feature/amazing-feature`
5. 发起 Pull Request

### 贡献规范

- 遵循 Bash 脚本最佳实践
- 关键步骤须有错误处理与 fallback
- 日志信息清晰、中英文均可
- 同步更新 README 相关章节

## 📝 许可证

本项目基于 [MIT 许可证](LICENSE) 开源。

## 🙏 致谢

- Debian 项目及所有维护者
- 阿里云、清华大学、中科大镜像站
- 社区用户的反馈与建议

## 📞 支持

- 📧 邮件：[everett7623@gmail.com](mailto:everett7623@gmail.com)
- 🐛 问题反馈：[GitHub Issues](https://github.com/everett7623/debian-auto-upgrade/issues)
- 💬 讨论区：[GitHub Discussions](https://github.com/everett7623/debian-auto-upgrade/discussions)

---

⭐ **如果这个项目对你有帮助，欢迎点个 Star！** ⭐

🛡️ **提示：** Debian 12 (Bookworm) 是当前稳定版，生产环境建议保持使用

## 📚 版本历史

| 版本 | 日期 | 主要变更 |
|------|------|----------|
| **v3.0** | 2026-04-02 | 全面重构：统一错误处理、自动清理旧 APT 源（修复 404）、GRUB 检测逻辑优化、磁盘空间预检、新增 `--mirror` 国内源支持 |
| **v2.6** | 2024-12-01 | 修复 GRUB 过度修复问题，改进重启确认机制 |
| **v2.5** | 2024-11-01 | 新增网络配置备份恢复，旧内核自动清理 |
| **v2.0** | 2024-06-01 | 新增 UEFI/BIOS 自动检测，NVMe 磁盘支持 |
| **v1.0** | 2024-01-01 | 初始版本，基础升级功能 |

详细变更记录见 [CHANGELOG.md](CHANGELOG.md)。
