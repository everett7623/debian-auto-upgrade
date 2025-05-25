# 基础升级示例

## 🎯 场景：Debian 11 升级到 Debian 12

### 前置条件
- Debian 11 (Bullseye) 系统
- 至少 4GB 可用磁盘空间
- 稳定的网络连接
- sudo 权限

### 升级步骤

1. **检查当前系统**
```bash
debian_upgrade.sh --version
debian_upgrade.sh --check
```

2. **执行升级**
```bash
debian_upgrade.sh
```

3. **升级完成后验证**
```bash
cat /etc/os-release
systemctl --failed
```

### 预期结果
- 系统版本从 Debian 11 升级到 Debian 12
- 所有服务正常运行
- 网络连接保持稳定
- 用户数据完整保留
