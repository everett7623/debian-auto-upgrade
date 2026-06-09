# Debian Auto Upgrade Tool

面向 Debian 服务器和 VPS 的逐版本升级辅助脚本。项目会检测当前版本、备份关键配置、暂时禁用附加 APT 源，并按 Debian 发行版顺序执行升级。

[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)
[![CI](https://github.com/everett7623/debian-auto-upgrade/actions/workflows/ci.yml/badge.svg)](https://github.com/everett7623/debian-auto-upgrade/actions/workflows/ci.yml)
[![Debian](https://img.shields.io/badge/Debian-11%20to%2013-A81D33.svg)](https://www.debian.org/)
[![Bash](https://img.shields.io/badge/Bash-4.4%2B-4EAA25.svg)](https://www.gnu.org/software/bash/)

> 发行版升级始终有中断服务、软件源不兼容和无法启动的风险。生产环境请先创建整机快照，并准备云厂商控制台、VNC 或串口控制台。

## 功能特性

- 只执行相邻 Debian 大版本升级，避免跨版本升级。
- 默认只升级到稳定版；测试版必须显式使用 `--allow-testing`。
- 升级前备份网络配置、APT 配置和接口信息。
- 同时识别传统 `.list` 与 Deb822 `.sources` 软件源。
- 暂时禁用附加源，避免第三方仓库阻断发行版升级。
- 等待 APT/dpkg 锁正常释放，不直接删除正在使用的锁文件。
- 升级后刷新 initramfs 和 GRUB 配置，但不会自动写入 MBR。
- 支持 Debian 官方源、阿里云、清华大学和中科大镜像。
- 提供检查、修复、调试和显式 GRUB 修复模式。

## 支持范围

| 当前版本 | 目标版本 | 主脚本状态 |
|---|---|---|
| Debian 11 Bullseye | Debian 12 Bookworm | 支持 |
| Debian 12 Bookworm | Debian 13 Trixie | 支持 |
| Debian 13 Trixie | Debian 14 Forky | 实验性，需 `--allow-testing` |
| Debian 8-10 | 下一相邻版本 | 仅保留历史脚本，不建议直接使用 |

Debian 8-10 已进入归档阶段，镜像地址、签名和中间升级要求与当前稳定版差异较大。`scripts/` 中的旧脚本仅供排查和迁移设计参考，详见 [scripts/README.md](scripts/README.md)。

## 快速开始

```bash
git clone https://github.com/everett7623/debian-auto-upgrade.git
cd debian-auto-upgrade
chmod +x debian_upgrade.sh

# 只检查，不修改系统
./debian_upgrade.sh --check

# 升级到下一个稳定版
sudo ./debian_upgrade.sh
```

也可以下载单文件运行：

```bash
curl -fL --proto '=https' --tlsv1.2 \
  -o debian_upgrade.sh \
  https://raw.githubusercontent.com/everett7623/debian-auto-upgrade/main/debian_upgrade.sh
chmod +x debian_upgrade.sh
sudo ./debian_upgrade.sh --check
```

下载后建议先核对 GitHub 中的文件内容或发布校验值，不要直接执行来源不明的脚本。

## 命令参数

| 参数 | 说明 |
|---|---|
| `-h, --help` | 显示帮助 |
| `-v, --version` | 显示当前 Debian 版本 |
| `-c, --check` | 检查版本、磁盘、内存、网络和引导状态 |
| `-d, --debug` | 输出详细诊断信息 |
| `--fix-only` | 修复 dpkg、依赖和 GRUB 配置，不升级 |
| `--fix-grub` | 显式执行 GRUB 修复 |
| `--force` | 跳过交互确认，仅用于受控自动化 |
| `--stable-only` | 只升级到稳定版，默认行为 |
| `--allow-testing` | 允许升级到下一测试版 |
| `--mirror <cn\|tuna\|ustc>` | 选择中国大陆镜像 |

## 常用示例

```bash
# 生产环境：先检查，再升级
sudo ./debian_upgrade.sh --check
sudo ./debian_upgrade.sh --stable-only

# 中国大陆 VPS 使用阿里云镜像
sudo ./debian_upgrade.sh --mirror cn

# 输出诊断信息
sudo ./debian_upgrade.sh --debug --check

# 修复中断的 dpkg/APT 状态
sudo ./debian_upgrade.sh --fix-only

# 明确需要时修复 GRUB
sudo ./debian_upgrade.sh --fix-grub
```

## 镜像源

| 参数值 | 镜像 |
|---|---|
| 默认 | `deb.debian.org` |
| `cn` | `mirrors.aliyun.com` |
| `tuna` | `mirrors.tuna.tsinghua.edu.cn` |
| `ustc` | `mirrors.ustc.edu.cn` |

镜像只影响 Debian 官方仓库。第三方仓库会在升级前禁用，升级完成并确认兼容目标版本后再逐项恢复。

## 升级流程

1. 检查 Debian 版本、可用空间、内存、网络和启动模式。
2. 保存网络接口及配置快照。
3. 停止当前活跃的自动更新单元，并等待 APT/dpkg 锁释放。
4. 修复未完成的 dpkg 配置和损坏依赖。
5. 备份并禁用 `sources.list.d` 中的 `.list` 与 `.sources`。
6. 写入目标版本官方源，执行 `apt-get update`。
7. 依次执行最小升级和完整升级。
8. 重建 initramfs、刷新 GRUB 配置并验证版本。
9. 恢复脚本主动停止的自动更新单元。

脚本不会自动恢复第三方源、不会自动改网卡名、不会自动重启网络服务，也不会在常规升级流程中写入磁盘引导区。

## 升级前检查清单

- 创建可回滚的 VPS 或虚拟机快照。
- 单独备份数据库、上传文件、密钥和业务配置。
- 确认控制台、VNC 或串口访问可用。
- 确认根分区至少有 4 GB 可用空间，`/boot` 至少有 200 MB。
- 完成当前版本全部更新并重启到最新内核。
- 检查 `apt-mark showhold`、`dpkg --audit` 和第三方仓库。
- 阅读目标版本的 Debian Release Notes。

## 常见问题

### APT update 返回 404 或缺少 Release 文件

检查目标版本、镜像和残留软件源：

```bash
grep -RhsE '^(deb|Types:|URIs:|Suites:)' \
  /etc/apt/sources.list /etc/apt/sources.list.d 2>/dev/null
sudo apt-get update
```

脚本创建的附加源备份目录形如 `/etc/apt/sources.list.d.bak_<时间戳>`。

### APT/dpkg 被锁定

不要手动删除锁文件。先确认占用进程：

```bash
sudo fuser -v /var/lib/dpkg/lock-frontend /var/lib/dpkg/lock
systemctl status apt-daily.service apt-daily-upgrade.service
```

随后等待任务完成，或确认任务异常后再由管理员处理。

### 包依赖或 dpkg 配置中断

```bash
sudo dpkg --configure -a
sudo apt-get --fix-broken install
sudo ./debian_upgrade.sh --fix-only
```

### 重启后无法引导

先通过救援环境确认根分区、EFI 分区和实际引导磁盘，再运行 `grub-install`。不要把示例磁盘名直接用于生产机器。系统仍可启动时可先执行：

```bash
sudo ./debian_upgrade.sh --fix-grub
```

### 升级后第三方软件不可用

从备份目录逐个恢复仓库，并先确认供应商已支持目标 Debian 版本。不要一次性恢复全部旧源。

## 开发与贡献

```bash
make check
```

开发环境、测试方法和提交要求见：

- [CONTRIBUTING.md](CONTRIBUTING.md)
- [docs/DEVELOPMENT.md](docs/DEVELOPMENT.md)
- [docs/SAFETY.md](docs/SAFETY.md)
- [SECURITY.md](SECURITY.md)

## 许可证

本项目使用 [MIT License](LICENSE)。

## 版本历史

详细变更见 [CHANGELOG.md](CHANGELOG.md)。
