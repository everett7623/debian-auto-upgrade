#!/bin/bash

# 修复 Debian 升级脚本遇到的问题

echo "修复 Debian 升级问题..."

# 1. 修复 sources.list
if grep -q '^\[INFO\]' /etc/apt/sources.list 2>/dev/null; then
    echo "检测到 sources.list 包含错误内容，正在修复..."
    
    # 恢复备份
    backup_files=$(ls -t /etc/apt/sources.list.backup.* 2>/dev/null | head -1)
    if [[ -n "$backup_files" ]]; then
        echo "找到备份文件: $backup_files"
        cp "$backup_files" /etc/apt/sources.list
        echo "已恢复备份的 sources.list"
    else
        # 手动创建正确的 sources.list
        echo "未找到备份，创建新的 sources.list..."
        
        # 检测当前版本
        if [[ -f /etc/debian_version ]]; then
            debian_version=$(cat /etc/debian_version)
            case "$debian_version" in
                10.*) codename="buster" ;;
                11.*) codename="bullseye" ;;
                12.*) codename="bookworm" ;;
                *) codename="bullseye" ;;  # 默认
            esac
        else
            codename="bullseye"
        fi
        
        # 创建新的 sources.list
        cat << EOF |  tee /etc/apt/sources.list > /dev/null
# Debian sources
deb http://deb.debian.org/debian $codename main contrib non-free
deb-src http://deb.debian.org/debian $codename main contrib non-free

# Security updates
deb http://security.debian.org/debian-security $codename-security main contrib non-free
deb-src http://security.debian.org/debian-security $codename-security main contrib non-free

# Updates
deb http://deb.debian.org/debian $codename-updates main contrib non-free
deb-src http://deb.debian.org/debian $codename-updates main contrib non-free
EOF
        echo "已创建新的 sources.list (Debian $codename)"
    fi
fi

# 2. 安装缺失的工具
if ! command -v bc &> /dev/null; then
    echo "安装 bc 命令..."
     apt-get update
     apt-get install -y bc
fi

# 3. 清理 APT 缓存
echo "清理 APT 缓存..."
 apt-get clean
 rm -rf /var/lib/apt/lists/*

# 4. 更新软件包列表
echo "更新软件包列表..."
 apt-get update

# 5. 修复可能的依赖问题
echo "修复依赖关系..."
 dpkg --configure -a
 apt-get --fix-broken install -y

echo "修复完成！"
echo ""
echo "现在可以重新运行升级脚本："
echo "  ./debian_upgrade.sh --check    # 检查状态"
echo "  ./debian_upgrade.sh            # 执行升级"
