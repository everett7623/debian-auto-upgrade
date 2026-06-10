# 更新日志

本文件记录 Debian Auto Upgrade Tool 的正式版本变更。

格式参考 [Keep a Changelog](https://keepachangelog.com/zh-CN/1.1.0/)，版本编号与 README 的版本历史保持一致。

## 未发布

## v3.6 - 2026-06-10

### VPS 兼容性

- ARM64 (aarch64) 架构支持：`fix_grub_mode` 根据 `uname -m` 自动选择正确的 GRUB 包和目标。
- 容器环境自动检测：识别 OpenVZ / LXC / Docker，跳过 GRUB 预设、initramfs 检查和引导磁盘警告。
- 非交互终端安全降级：缺失 `/dev/tty` 时（cron / systemd 环境）优雅回退，不再崩溃。
- EFI 目录多策略检测：`findmnt` → 常见路径 → `/etc/fstab` 逐层查找 ESP 挂载点。
- 网络检测 HTTP 回退：ICMP 被阻断（国内常见）时自动尝试 wget/curl 连接镜像源。
- `--self-update` CDN 回退：GitHub 不可达时自动尝试 jsDelivr CDN 地址。

### 修复

- 修复 `fix_only_mode` 缺少 `stop_apt_units` 导致 apt-daily 定时任务抢占锁的问题。
- 修复 GPG 恢复路径在 404 和 GPG 错误同时出现时不可达（重排分支顺序：GPG → 404）。
- 修复 `detect_boot_disk` 策略 3 中 `blkid -U` 缺少 `$USE_SUDO` 前缀。
- 修复 `--mirror` 无效值时静默回退到官方源，改为主动警告。
- 修复 `check_upgrade` 将 oldstable / oldoldstable 误标为 "不稳定版本"。

### 优化

- 版本元数据从硬编码 case 语句重构为关联数组（`DEBIAN_CODENAME` / `DEBIAN_STATUS` / `DEBIAN_NEXT`）。
- 抽取 `get_old_kernels()` 共享函数，消除 `clean_old_kernels` 和 `cleanup_mode` 中约 20 行重复代码。
- 升级日志文件拆分：`apt-upgrade.log` / `apt-dist-upgrade.log` / `initramfs-post.log` 独立保存。
- `self_update_mode` 添加 wget 存在性检查和 curl 替代方案提示。
- `safe_read()` 辅助函数统一处理交互输入和 tty 降级。

## v3.5 - 2026-06-10

### 新增

- 新增 `--cleanup` 升级后五步清理模式（废弃包 → rc 残留 → 旧内核 → APT 缓存 → .dpkg-* 文件）。
- 新增 `--self-update` 脚本自动更新（从 GitHub 下载最新版，语法检查后替换）。
- 新增 `--preflight` 深度检查模式，不切换软件源即可验证动态库、initramfs 和 dpkg 状态。
- 升级前预构建当前内核 initramfs，失败时在修改 APT 源之前安全停止。
- 检查 `fsck` 动态库依赖和 `/etc/ld.so.preload` 中的非常规路径。

### 修复

- 修复跨版本 GPG 签名验证失败：切换源前更新 `debian-archive-keyring`，遇 NO_PUBKEY 时使用 `[trusted=yes]` 临时绕过。
- 修复云镜像 / 容器环境下 initramfs 预检因缺少 `/var/tmp` 失败。
- 修复最小升级失败后仍继续执行完整升级的问题。
- 修复完整升级失败后自动重复执行耗时包管理操作的问题。
- 错误退出时不再通过 ERR trap 自动重试包管理修复。

### 性能

- APT 更新默认不再下载源码索引和翻译索引。
- APT 已生成最新内核 initramfs 时跳过重复重建。
- 每个升级阶段最多执行一次，失败后保留日志并立即停止。

## v3.3 - 2026-06-09

### 安全

- 等待 APT/dpkg 锁正常释放，不再直接删除仍可能被进程占用的锁文件。
- 常规升级流程不再自动修改网卡名称或重启网络服务。
- 常规升级流程不再写入 MBR 或无条件重装 GRUB。
- 升级完成后不再自动执行 `autoremove`，避免误删仍需人工核对的依赖。
- 只恢复脚本本次主动停止的自动更新单元。

### 新增

- 支持识别、备份并禁用 Deb822 `.sources` 软件源。
- 新增独立的单次运行临时目录，避免固定临时文件冲突。
- 新增 Bash 冒烟测试和危险操作模式检查。
- 新增 GitHub Actions CI、`Makefile`、EditorConfig 和 Git 属性配置。
- 新增贡献指南、安全策略、开发指南、安全边界及历史脚本说明。

### 修复

- 日志改为写入标准错误，避免 `--debug` 输出污染命令替换结果。
- 使用 `sudo tee` 正确写入 root 所有的网络配置快照。
- 修复清理 `/boot` 中 `.old` 和 `.bak` 文件时的 `find` 条件优先级。
- 修复脚本被 `source` 时入口保护返回非零并触发调用方 `set -e` 的问题。

### 文档

- 基于原版结构更新 README，保留原有功能介绍、升级路径、使用示例、故障排查、支持方式和版本历史。
- 明确统一主脚本支持 Debian 11-13；Debian 8-10 脚本仅作为历史迁移参考。

## v3.2 - 2026-06-01

### 变更

- 更新 Debian 13 Trixie 状态为正式稳定版。
- Debian 12 → 13 升级不再需要 `--allow-testing`。
- Debian 13 → 14 Forky 升级需要显式使用 `--allow-testing`。
- 更新帮助信息、升级路径说明和 README。

## v3.1 - 2026-06-01

### 修复

- 修复 Debian 12 已是最新稳定版时升级提示不显示的问题。
- 修正 `main_upgrade()` 中提示逻辑的判断条件。

### 变更

- 更新 Debian 13 Trixie 的版本状态说明。
- 更新 `--help` 中的升级路径。

## v3.0 - 2026-04-02

### 变更

- 全面重构统一升级脚本，提高健壮性与兼容性。
- 统一关键步骤的错误处理和恢复流程。
- 改进 Debian 版本检测及升级目标判断。

### 新增

- 新增 `--mirror`，支持阿里云、清华大学和中科大镜像。
- 新增磁盘空间和 `/boot` 空间预检。
- 新增 APT 源备份、旧 backports 处理及第三方源清理。
- 新增 UEFI/BIOS、NVMe、virtio 和 Xen 引导磁盘检测。
- 新增完整帮助信息、调试日志和升级前后验证。

### 修复

- 修复 `sources.list.d/` 中旧源残留导致的 APT 冲突和 404。
- 改进 GRUB 检测逻辑，减少误判和过度修复。
- 改进部分 VPS 无法正确识别 Debian 版本的问题。

## v2.6 - 2024-12-01

### 修复

- 修复 GRUB 过度修复问题。
- 改进重启前的二次确认机制。
- 降低自动引导修复对 VPS 启动配置的影响。

## v2.5 - 2024-11-01

### 新增

- 新增网络接口配置、IP 地址和路由信息备份。
- 新增升级后网络配置检查与恢复辅助。
- 新增旧内核清理，用于释放 `/boot` 空间。

## v2.0 - 2024-06-01

### 新增

- 新增 UEFI 与 BIOS 启动模式自动检测。
- 新增 NVMe、virtio 和 Xen 磁盘支持。
- 改进 GRUB 安装磁盘识别。
- 增强 VPS 和虚拟机环境兼容性。

## v1.0 - 2024-01-01

### 新增

- 发布初始版本。
- 提供 Debian 基础版本检测和相邻版本升级流程。
- 提供 APT 源更新、软件包升级及基础错误处理。
- 提供命令行帮助和升级确认。

---

## 版本支持说明

| 工具版本 | 主脚本 Debian 支持范围 | 说明 |
|---|---|---|
| 3.3.x | Debian 11-13 | 当前维护版本；Debian 14 仅实验性支持 |
| 3.0.x-3.2.x | Debian 8-13 | 历史统一脚本版本 |
| 2.x | Debian 8-12 | 历史版本，安全行为和版本状态可能已过时 |
| 1.x | Debian 8-11 | 初始版本，不建议继续使用 |

Debian 8-10 已进入归档范围。仓库 `scripts/` 中的分版本脚本仅供历史追踪和迁移设计参考，不作为当前生产入口。

## 升级说明

### 从 v3.2 升级到 v3.3

- 建议直接替换现有 `debian_upgrade.sh`。
- 命令行参数保持兼容。
- 第三方 `.list` 和 `.sources` 会在升级前备份并禁用。
- 常规升级不再自动写入 MBR、重启网络或执行 `autoremove`。
- 执行前仍应创建系统快照并确认控制台访问可用。

### 从 v2.x 升级到 v3.x

- v3 对升级流程和安全边界进行了较大调整。
- 请重新阅读 README 的支持范围和升级前检查清单。
- 不要沿用旧版脚本对 APT 锁、网络服务和 GRUB 的自动处理假设。
- 生产使用前应在可回滚的 Debian 虚拟机中完成验证。
