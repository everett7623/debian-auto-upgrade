# 🚀 Debian Auto Upgrade Tool

> 专为 Debian 系统设计的智能逐级升级工具，支持 VPS 环境优化、自动错误修复与保守升级策略

[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](https://opensource.org/licenses/MIT)
[![GitHub release](https://img.shields.io/github/release/everett7623/debian-auto-upgrade.svg)](https://github.com/everett7623/debian-auto-upgrade/releases)
[![CI](https://github.com/everett7623/debian-auto-upgrade/actions/workflows/ci.yml/badge.svg)](https://github.com/everett7623/debian-auto-upgrade/actions/workflows/ci.yml)
[![Debian](https://img.shields.io/badge/Debian-11--13-red.svg)](https://www.debian.org/)
[![Bash](https://img.shields.io/badge/Language-Bash-green.svg)](https://www.gnu.org/software/bash/)
[![Version](https://img.shields.io/badge/Version-3.3.1-brightgreen.svg)](https://github.com/everett7623/debian-auto-upgrade/releases)

专为 Debian 系统打造的自动化升级脚本，支持从旧版本安全逐级升级到最新稳定版本。针对 VPS 环境深度优化，具备完善的错误恢复与容错能力。

> ⚠️ 发行版升级始终存在服务中断、软件源不兼容和无法启动的风险。生产环境请先创建整机快照，并准备云厂商控制台、VNC 或串口控制台。

## ✨ 功能特性

- 🔄 **逐级安全升级** — 主脚本支持 Debian 11 → 12 → 13 相邻版本升级，避免跨版本风险
- 🛡️ **智能版本管控** — 默认阻止意外升级到不稳定版本，`--stable-only` 模式保障生产安全
- 🌍 **国内镜像支持** — 一键切换阿里云 / 清华 / 中科大镜像源，国内 VPS 推荐使用
- 🔧 **APT 源安全处理** — 同时识别 `.list` 与 Deb822 `.sources`，升级前备份并暂时禁用附加源
- 🔒 **APT 锁安全等待** — 等待 APT/dpkg 锁正常释放，不直接删除仍被进程占用的锁文件
- 💾 **配置完整备份** — 升级前自动备份网络配置、APT 源等关键文件
- 🖥️ **GRUB 保守处理** — 自动识别 UEFI/BIOS，常规升级仅刷新配置，不自动写入 MBR
- 📊 **彩色日志输出** — 带时间戳的分级日志，`--debug` 模式输出完整诊断信息
- 🔍 **升级前后验证** — 自动校验升级结果，失败时触发错误恢复流程
- ⚠️ **风险分级确认** — 稳定版单次确认，测试版强制输入 `YES` 二次确认

## 🎯 支持的升级路径

| 源版本 | 目标版本 | 状态 | 安全性 | 说明 |
|---|---|---|---|---|
| Debian 8 (Jessie) | Debian 9 (Stretch) | 📚 历史脚本 | ⚠️ 谨慎 | 仅供迁移研究，不属于主脚本支持范围 |
| Debian 9 (Stretch) | Debian 10 (Buster) | 📚 历史脚本 | ⚠️ 谨慎 | 仅供迁移研究，不属于主脚本支持范围 |
| Debian 10 (Buster) | Debian 11 (Bullseye) | 📚 历史脚本 | ⚠️ 谨慎 | 仅供迁移研究，不属于主脚本支持范围 |
| Debian 11 (Bullseye) | Debian 12 (Bookworm) | ✅ 支持 | 🔒 稳定 | 主脚本支持 |
| Debian 12 (Bookworm) | Debian 13 (Trixie) | ✅ 支持 | 🔒 稳定 | **当前推荐**，直接升级无需额外参数 |
| Debian 13 (Trixie) | Debian 14 (Forky) | ⚠️ 实验性 | 🧪 谨慎 | 需 `--allow-testing`，不建议生产环境 |

> **建议：** 生产系统请升级到 Debian 13 (Trixie)，这是当前稳定版。Debian 8-10 已进入归档范围，镜像、签名和中间升级要求复杂，请先阅读 [历史脚本说明](scripts/README.md) 及 Debian 官方 Release Notes。

## 🚀 快速开始

### 一键安装运行

```bash
wget -O debian_upgrade.sh https://raw.githubusercontent.com/everett7623/debian-auto-upgrade/main/debian_upgrade.sh \
  && chmod +x debian_upgrade.sh \
  && sudo ./debian_upgrade.sh --preflight \
  && sudo ./debian_upgrade.sh
```

也可以使用带 HTTPS 限制的 `curl` 下载：

```bash
curl -fL --proto '=https' --tlsv1.2 \
  -o debian_upgrade.sh \
  https://raw.githubusercontent.com/everett7623/debian-auto-upgrade/main/debian_upgrade.sh
chmod +x debian_upgrade.sh
sudo ./debian_upgrade.sh --check
```

> 下载后建议先核对 GitHub 中的文件内容或发布校验值，不要直接执行来源不明的脚本。

### 基本用法

```bash
# 检查当前版本与可用升级
sudo ./debian_upgrade.sh --check

# 深度检查 initramfs、动态库和 dpkg 状态，不切换软件源
sudo ./debian_upgrade.sh --preflight

# 升级到最新稳定版（推荐）
sudo ./debian_upgrade.sh

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
| `--preflight` | 深度检查 initramfs、动态库依赖和 dpkg 状态，不执行升级 |
| `-d, --debug` | 启用调试模式，输出详细诊断信息 |
| `--fix-only` | 修复 dpkg、依赖和 GRUB 配置，不执行升级 |
| `--fix-grub` | 显式执行 GRUB 引导修复 |
| `--force` | 跳过所有确认提示（慎用） |
| `--stable-only` | 仅升级到稳定版（默认，推荐） |
| `--allow-testing` | 允许升级到 Debian 14 Forky（testing） |
| `--mirror <cn\|tuna\|ustc>` | 使用指定国内镜像源 |

## 💡 使用示例

### 生产服务器（推荐）

```bash
# 检查状态，不执行升级
sudo ./debian_upgrade.sh --check

# 深度预检通过后再升级
sudo ./debian_upgrade.sh --preflight

# 升级到 Debian 13 Trixie（当前稳定版）
sudo ./debian_upgrade.sh --stable-only

# 国内服务器使用阿里云源
sudo ./debian_upgrade.sh --mirror cn
```

### 开发 / 测试环境

```bash
# 允许升级到 Forky 测试版（需手动输入 YES 确认）
sudo ./debian_upgrade.sh --allow-testing

# 自动化场景强制升级（极度谨慎）
sudo ./debian_upgrade.sh --force --stable-only

# 调试模式排查问题
sudo ./debian_upgrade.sh --debug --check
```

### 系统修复

```bash
# 等待 APT 锁释放，修复 dpkg、依赖和 GRUB 配置
sudo ./debian_upgrade.sh --fix-only

# 专门修复 GRUB 引导（确认目标磁盘后使用）
sudo ./debian_upgrade.sh --fix-grub
```

## 🌍 国内镜像源

通过 `--mirror` 参数一键切换，显著提升国内 VPS 下载速度：

| 参数值 | 镜像源 | 适用场景 |
|--------|--------|----------|
| `cn` | 阿里云 mirrors.aliyun.com | 国内通用 |
| `tuna` | 清华大学 mirrors.tuna.tsinghua.edu.cn | 教育网用户 |
| `ustc` | 中科大 mirrors.ustc.edu.cn | 教育网备选 |
| _(不填)_ | Debian 官方 deb.debian.org | 境外服务器 |

镜像选项只影响 Debian 官方仓库。第三方仓库会在升级前暂时禁用，升级完成并确认供应商支持目标 Debian 版本后再逐项恢复。

## 🔧 APT 源自动清理（安全处理）

升级前脚本会自动处理以下问题，降低常见的 **404 / Release 文件缺失** 风险：

- 自动备份 `/etc/apt/sources.list.d/`
- 同时识别并禁用传统 `.list` 与 Deb822 `.sources` 附加源
- 注释掉主 `sources.list` 中启用的 backports 行
- `apt-get update` 检测到 404 时再次禁用残留附加源并重试
- 写入新版 `sources.list` 时适配 Debian 11 的安全源格式和 Debian 12+ 的 `non-free-firmware`
- 升级后不自动恢复第三方源，避免旧仓库再次污染软件包状态

附加源备份目录形如：

```text
/etc/apt/sources.list.d.bak_<时间戳>
```

## 📦 升级策略

### 四阶段升级流程

1. **升级前检查** — 检查版本、磁盘、内存、网络、启动模式、动态库依赖及 initramfs 生成能力
2. **最小升级** (`apt-get upgrade`) — 先处理不涉及复杂依赖变更的软件包
3. **完整升级** (`apt-get dist-upgrade`) — 执行完整发行版升级
4. **升级后处理** — 验证最新内核 initramfs、刷新 GRUB 配置并验证目标版本

### 安全边界

- 不直接删除 APT/dpkg 锁文件
- 不自动修改网卡名称
- 不自动重启网络服务
- 常规升级不写入 MBR 或无条件重装引导器
- 升级后不自动执行 `autoremove`
- 只恢复脚本本次主动停止的自动更新单元
- 最小升级失败后立即停止，不再带病执行完整升级
- 完整升级失败后不自动重复整套升级流程
- APT 默认不下载源码索引和翻译索引
- APT 已生成最新内核 initramfs 时不再重复重建全部旧内核

完整约束见 [docs/SAFETY.md](docs/SAFETY.md)。

### 自动备份内容

- APT 源配置（`sources.list` + `sources.list.d/`）
- 网络接口配置（`/etc/network/interfaces`、systemd-networkd）
- 升级前 IP 地址与路由表快照
- 升级前网络接口名称

## 💻 系统要求

### 最低要求

- 主脚本：Debian 11、12 或 13
- Bash 4.4 或更高版本
- 根分区可用空间 ≥ 2GB
- 可用内存 ≥ 256MB
- 稳定的互联网连接
- root 权限或可用的 `sudo`

### 生产环境建议

- 根分区可用空间 ≥ 4GB
- `/boot` 分区可用空间 ≥ 200MB
- 可用内存 ≥ 1GB
- 已完成当前版本全部更新并重启到最新内核
- 具备 sudo 权限的用户账户
- 具备可回滚快照及带外控制台访问

## ⚠️ 重要安全提示

### 升级前必做

- 📸 创建 VPS / 虚拟机整机快照
- 💾 单独备份数据库、上传文件、密钥和业务配置
- 📝 记录当前网络配置（IP、网关、DNS）
- 🔑 确保 VNC / 控制台 / 串口访问可用（SSH 升级期间可能中断）
- 📦 检查 `apt-mark showhold`、`dpkg --audit` 和第三方仓库
- 📖 阅读目标版本的 Debian Release Notes

### Debian 11 用户须知

- Debian 11 已是 oldoldstable，建议先升级到 Debian 12
- 每次只升级一个大版本，不要直接跨越到 Debian 13
- 完成 11 → 12 后应重启并验证服务，再继续后续升级

### Debian 12 用户须知

- ✅ Debian 13 (Trixie) 已于 2025-08-09 正式发布，**推荐规划升级**
- 🚀 直接运行脚本即可升级，无需 `--allow-testing`
- 🛡️ Debian 12 仍可继续使用，但应提前规划版本迁移
- 🔌 升级前确认关键第三方软件已支持 Debian 13

### Debian 13 用户须知

- ✅ 已是当前稳定版，**建议保持**
- ⚠️ 升级到 Debian 14 (Forky) 即进入 testing 分支，存在不稳定风险
- 🛡️ 使用 `--stable-only`（默认）可防止误升级到测试版
- 💡 测试版升级需手动输入 `YES` 进行二次确认

## 🔒 确认机制

| 升级类型 | 确认方式 |
|----------|----------|
| 稳定版 → 稳定版 | `[y/N]` 单次确认 |
| 稳定版 → 测试版 | 需手动输入 `YES`（大写）并阅读风险说明 |
| `--stable-only` 模式 | 不提供测试版升级选项 |
| `--force` 模式 | 跳过交互确认（极度谨慎） |

`--force` 只跳过交互确认，不代表操作无风险，也不能替代快照、备份和控制台访问。

## 🐛 常见问题

### ❓ apt-get update 报 404 或缺少 Release 文件

常见原因是旧版 backports 或第三方源在升级后失效。脚本会备份并禁用附加源；若问题仍存在，可先检查当前配置：

```bash
grep -RhsE '^(deb|Types:|URIs:|Suites:)' \
  /etc/apt/sources.list /etc/apt/sources.list.d 2>/dev/null
sudo apt-get update
```

不要一次性恢复全部旧源，应从备份目录逐项确认目标版本兼容性。

### ❓ APT 锁定错误

不要直接删除锁文件。先确认占用进程：

```bash
sudo fuser -v /var/lib/dpkg/lock-frontend /var/lib/dpkg/lock
systemctl status apt-daily.service apt-daily-upgrade.service
```

确认其他包管理任务结束后，可运行：

```bash
sudo ./debian_upgrade.sh --fix-only
```

### ❓ 重启后系统无法引导

先通过救援环境确认根分区、EFI 分区和实际引导磁盘，不要直接套用示例磁盘名。

```bash
# 系统仍可启动时：
sudo ./debian_upgrade.sh --fix-grub

# 救援环境中按实际磁盘和挂载情况处理：
grub-install /dev/sdX
update-grub
```

### ❓ 包依赖冲突

脚本会自动尝试修复依赖。若问题持续：

```bash
sudo dpkg --configure -a
sudo apt-get --fix-broken install
sudo ./debian_upgrade.sh --fix-only
```

### ❓ initramfs 报 `hooks/fsck failed` 或出现 `/var/adm/<UUID>`

这不是普通下载失败。若 `mkinitramfs` 输出 `/var/adm/<UUID>` 等非常规动态库路径，应优先排查 `/etc/ld.so.preload` 注入或系统文件被修改：

```bash
sudo cat /etc/ld.so.preload
sudo env --unset=LD_PRELOAD ldd /sbin/fsck
sudo ./debian_upgrade.sh --preflight
```

在确认异常库来源前，不要创建缺失目录绕过错误，也不要重启到缺少 initrd 的新内核。建议先创建快照并通过服务商控制台或安全工具完成系统排查。

### ❓ 升级后网络断开

脚本不会自动改网卡名或重启网络服务。请通过 VPS 控制台登录后检查：

```bash
ip addr show
ip route show
systemctl status networking systemd-networkd NetworkManager
```

网络配置备份路径会显示在升级日志中，请核对后人工恢复。

### ❓ 升级后第三方软件不可用

从 `/etc/apt/sources.list.d.bak_<时间戳>` 逐个恢复仓库，并先确认供应商已支持目标 Debian 版本。不要一次恢复全部旧源。

## 📄 问题反馈

提交 Issue 时请附上以下信息：

- 当前系统版本：`cat /etc/os-release`
- 错误日志：使用 `--debug` 参数重新运行并复制输出
- 系统环境：物理机 / KVM / OpenVZ / 云厂商
- 启动方式：UEFI / BIOS
- 网络环境：是否使用代理 / 防火墙 / 国内镜像
- 已隐藏密码、令牌、私有地址等敏感信息的 APT 配置

安全问题请先阅读 [SECURITY.md](SECURITY.md)，不要在公开 Issue 中提交密钥、凭据或业务数据。

## 🤝 参与贡献

欢迎提交 Issue 和 Pull Request！

### 开发流程

1. Fork 本仓库
2. 创建功能分支：`git checkout -b feature/amazing-feature`
3. 安装开发依赖：`sudo apt-get install bash shellcheck make git`
4. 运行检查：`make check`
5. 提交变更：`git commit -m 'Add amazing feature'`
6. 推送分支：`git push origin feature/amazing-feature`
7. 发起 Pull Request

### 贡献规范

- 遵循 Bash 脚本最佳实践
- 关键步骤须有明确错误处理
- 默认流程不得删除包管理器锁、写入 MBR 或重启网络
- 日志信息应清晰，不得输出凭据
- 修改行为时同步更新 README、CHANGELOG 和测试
- 在 Pull Request 中说明测试过的 Debian 版本和启动方式

详细开发说明：

- [CONTRIBUTING.md](CONTRIBUTING.md)
- [docs/DEVELOPMENT.md](docs/DEVELOPMENT.md)
- [docs/SAFETY.md](docs/SAFETY.md)
- [scripts/README.md](scripts/README.md)

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

🛡️ **提示：** Debian 13 (Trixie) 是当前稳定版；生产环境升级前请先创建快照并确认控制台可用。

## 📚 版本历史

| 版本 | 日期 | 主要变更 |
|------|------|----------|
| **v3.3.1** | 2026-06-09 | 修复失败后重复执行导致耗时过长：新增 initramfs/动态库预检与 `--preflight`；首次升级失败立即停止；精简 APT 索引；跳过重复 initramfs 重建 |
| **v3.3** | 2026-06-09 | 安全加固：等待 APT 锁正常释放；支持 `.sources`；取消默认改网卡、重启网络、写 MBR 和 `autoremove`；补充测试、CI 与开发文档 |
| **v3.2** | 2026-06-01 | 更新 Debian 13 Trixie 为正式稳定版：12→13 直接升级无需 `--allow-testing`，13→14 (Forky) 需 `--allow-testing`，同步更新 README |
| **v3.1** | 2026-06-01 | 修复 Debian 12 已是最新稳定版时升级提示不显示的 bug |
| **v3.0** | 2026-04-02 | 全面重构：统一错误处理、自动清理旧 APT 源（修复 404）、GRUB 检测逻辑优化、磁盘空间预检、新增 `--mirror` 国内源支持 |
| **v2.6** | 2024-12-01 | 修复 GRUB 过度修复问题，改进重启确认机制 |
| **v2.5** | 2024-11-01 | 新增网络配置备份恢复，旧内核自动清理 |
| **v2.0** | 2024-06-01 | 新增 UEFI/BIOS 自动检测，NVMe 磁盘支持 |
| **v1.0** | 2024-01-01 | 初始版本，基础升级功能 |

详细变更记录见 [CHANGELOG.md](CHANGELOG.md)。
