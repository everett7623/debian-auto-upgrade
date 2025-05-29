#!/bin/bash

# 测试重启后升级状态的脚本
# 用于手动创建升级状态文件来测试功能

echo "🧪 创建测试升级状态..."

# 获取当前版本
get_current_version() {
    local version_id=""
    
    if [[ -f /etc/os-release ]]; then
        version_id=$(grep "^VERSION_ID=" /etc/os-release | cut -d'"' -f2 2>/dev/null || echo "")
    fi
    
    if [[ -z "$version_id" ]] && [[ -f /etc/debian_version ]]; then
        local debian_version=$(cat /etc/debian_version 2>/dev/null || echo "")
        case "$debian_version" in
            8.*|jessie*) version_id="8" ;;
            9.*|stretch*) version_id="9" ;;
            10.*|buster*) version_id="10" ;;
            11.*|bullseye*) version_id="11" ;;
            12.*|bookworm*) version_id="12" ;;
            13.*|trixie*) version_id="13" ;;
            *) version_id="11" ;;  # 默认值
        esac
    fi
    
    echo "$version_id"
}

current_version=$(get_current_version)
previous_version=$((current_version - 1))

echo "当前版本: Debian $current_version"
echo "模拟从 Debian $previous_version 升级到 Debian $current_version"

# 创建状态文件
upgrade_state_file="/var/lib/debian_upgrade_state"
backup_state_file="/etc/debian_upgrade_state.backup"

# 确保目录存在
sudo mkdir -p /var/lib 2>/dev/null || true
sudo mkdir -p /etc 2>/dev/null || true

# 创建主状态文件
cat << EOF | sudo tee "$upgrade_state_file" > /dev/null
PREVIOUS_VERSION=$previous_version
CURRENT_VERSION=$current_version
TARGET_VERSION=$current_version
UPGRADE_TIME=$(date '+%Y-%m-%d %H:%M:%S')
SCRIPT_VERSION=2.2
REBOOT_PENDING=1
EOF

# 创建备份状态文件
sudo cp "$upgrade_state_file" "$backup_state_file"

# 设置权限
sudo chmod 644 "$upgrade_state_file"
sudo chmod 644 "$backup_state_file"

echo "✅ 测试状态文件已创建:"
echo "   主文件: $upgrade_state_file"
echo "   备份: $backup_state_file"
echo
echo "📋 状态文件内容:"
sudo cat "$upgrade_state_file"
echo
echo "🧪 现在可以运行以下命令测试:"
echo "   ./debian_upgrade.sh --check-state"
echo "   ./debian_upgrade.sh"
echo
echo "🗑️ 要清理测试状态，运行:"
echo "   sudo rm -f $upgrade_state_file $backup_state_file"
