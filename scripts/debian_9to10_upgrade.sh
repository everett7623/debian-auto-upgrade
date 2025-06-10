#!/bin/bash

# Debian 9 (Stretch) 到 Debian 10 (Buster) 升级脚本
# 版本: 1.0

set -e

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# 日志函数
log_info() {
    echo -e "${BLUE}[INFO]${NC} $(date '+%H:%M:%S') - $1"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $(date '+%H:%M:%S') - $1"
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $(date '+%H:%M:%S') - $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $(date '+%H:%M:%S') - $1"
}

# 检查root权限
check_root() {
    if [[ $EUID -ne 0 ]]; then
        log_error "此脚本必须以root权限运行"
        exit 1
    fi
}

# 检查当前版本
check_version() {
    if ! grep -q "^9\." /etc/debian_version 2>/dev/null; then
        log_error "此脚本仅适用于Debian 9 (Stretch)"
        log_error "当前版本: $(cat /etc/debian_version)"
        exit 1
    fi
}

# 检查并修复已知问题
fix_known_issues() {
    log_info "检查并修复已知问题..."
    
    # 修复可能的locale问题
    if ! locale -a | grep -q "en_US.utf8"; then
        log_info "生成en_US.UTF-8 locale..."
        echo "en_US.UTF-8 UTF-8" >> /etc/locale.gen
        locale-gen
    fi
    
    # 确保基本工具存在
    log_info "安装必要的基本工具..."
    apt-get update
    apt-get install -y apt-transport-https ca-certificates gnupg
}

# 备份重要文件
backup_files() {
    log_info "备份重要配置文件..."
    local backup_dir="/root/debian_upgrade_backup_$(date +%Y%m%d_%H%M%S)"
    mkdir -p "$backup_dir"
    
    # 备份sources.list
    cp -r /etc/apt/sources.list* "$backup_dir/" 2>/dev/null || true
    
    # 备份重要配置
    for dir in /etc/network /etc/systemd /etc/default /etc/ssh; do
        if [[ -d "$dir" ]]; then
            cp -r "$dir" "$backup_dir/" 2>/dev/null || true
        fi
    done
    
    # 备份已安装包列表
    dpkg --get-selections > "$backup_dir/package_list.txt"
    
    log_success "备份完成: $backup_dir"
}

# 清理和修复APT
fix_apt() {
    log_info "清理APT缓存和修复依赖..."
    
    # 停止自动更新服务
    systemctl stop apt-daily.timer 2>/dev/null || true
    systemctl stop apt-daily-upgrade.timer 2>/dev/null || true
    
    # 等待APT锁释放
    while fuser /var/lib/dpkg/lock >/dev/null 2>&1; do
        log_info "等待其他APT进程完成..."
        sleep 2
    done
    
    # 清理锁文件
    rm -f /var/lib/dpkg/lock-frontend 2>/dev/null || true
    rm -f /var/lib/dpkg/lock 2>/dev/null || true
    rm -f /var/cache/apt/archives/lock 2>/dev/null || true
    
    # 修复dpkg
    dpkg --configure -a 2>/dev/null || true
    
    # 修复依赖
    apt-get --fix-broken install -y 2>/dev/null || true
    
    # 清理缓存
    apt-get clean
    apt-get autoclean
}

# 更新到Debian 10
upgrade_to_buster() {
    log_info "开始升级到Debian 10 (Buster)..."
    
    # 更新当前系统
    log_info "更新当前系统..."
    apt-get update
    DEBIAN_FRONTEND=noninteractive apt-get upgrade -y
    DEBIAN_FRONTEND=noninteractive apt-get dist-upgrade -y
    
    # 备份并更新sources.list
    log_info "更新软件源到Buster..."
    cp /etc/apt/sources.list /etc/apt/sources.list.stretch.bak
    
    cat > /etc/apt/sources.list << EOF
# Debian 10 (Buster)
deb http://deb.debian.org/debian buster main contrib non-free
deb-src http://deb.debian.org/debian buster main contrib non-free

# Security updates
deb http://deb.debian.org/debian-security buster/updates main contrib non-free
deb-src http://deb.debian.org/debian-security buster/updates main contrib non-free

# Updates
deb http://deb.debian.org/debian buster-updates main contrib non-free
deb-src http://deb.debian.org/debian buster-updates main contrib non-free
EOF

    # 清理第三方源
    if [[ -d /etc/apt/sources.list.d ]]; then
        log_info "临时禁用第三方源..."
        mkdir -p /etc/apt/sources.list.d.bak
        mv /etc/apt/sources.list.d/*.list /etc/apt/sources.list.d.bak/ 2>/dev/null || true
    fi
    
    # 更新软件包列表
    log_info "更新软件包列表..."
    apt-get update
    
    # 执行最小升级
    log_info "执行最小系统升级..."
    DEBIAN_FRONTEND=noninteractive apt-get upgrade -y \
        -o Dpkg::Options::="--force-confdef" \
        -o Dpkg::Options::="--force-confold"
    
    # 安装新内核
    log_info "安装新内核..."
    DEBIAN_FRONTEND=noninteractive apt-get install -y linux-image-amd64 || \
        DEBIAN_FRONTEND=noninteractive apt-get install -y linux-image-686 || true
    
    # 执行完整升级
    log_info "执行完整系统升级..."
    DEBIAN_FRONTEND=noninteractive apt-get dist-upgrade -y \
        -o Dpkg::Options::="--force-confdef" \
        -o Dpkg::Options::="--force-confold"
    
    # 清理旧包
    log_info "清理系统..."
    apt-get autoremove -y --purge
    apt-get autoclean
}

# 升级后检查和修复
post_upgrade_check() {
    log_info "执行升级后检查和修复..."
    
    # 更新GRUB
    if command -v update-grub >/dev/null 2>&1; then
        log_info "更新GRUB配置..."
        update-grub
    fi
    
    # 重新生成initramfs
    if command -v update-initramfs >/dev/null 2>&1; then
        log_info "更新initramfs..."
        update-initramfs -u -k all
    fi
    
    # 检查并修复网络配置
    log_info "检查网络配置..."
    if [[ -f /etc/network/interfaces ]]; then
        # 备份网络配置
        cp /etc/network/interfaces /etc/network/interfaces.bak.$(date +%s)
        
        # 确保网络接口正常
        systemctl restart networking 2>/dev/null || true
    fi
    
    # 检查SSH配置
    if [[ -f /etc/ssh/sshd_config ]]; then
        log_info "检查SSH配置..."
        # 确保SSH允许root登录（如果需要）
        if ! grep -q "^PermitRootLogin" /etc/ssh/sshd_config; then
            echo "PermitRootLogin yes" >> /etc/ssh/sshd_config
        fi
        systemctl restart ssh 2>/dev/null || systemctl restart sshd 2>/dev/null || true
    fi
    
    # 检查系统服务
    log_info "检查关键系统服务..."
    systemctl daemon-reload
    
    # 重启必要的服务
    for service in ssh networking systemd-resolved; do
        if systemctl is-enabled "$service" >/dev/null 2>&1; then
            systemctl restart "$service" 2>/dev/null || true
        fi
    done
    
    # 验证版本
    local new_version=$(cat /etc/debian_version)
    if [[ "$new_version" =~ ^10\. ]]; then
        log_success "升级成功！当前版本: Debian 10 (Buster)"
    else
        log_warning "升级可能未完成，请检查系统版本: $new_version"
    fi
}

# 主函数
main() {
    echo "========================================="
    echo "Debian 9 → 10 升级脚本"
    echo "========================================="
    
    check_root
    check_version
    
    echo
    read -p "是否开始升级到Debian 10? [y/N]: " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        log_info "升级已取消"
        exit 0
    fi
    
    # 执行升级步骤
    fix_known_issues
    backup_files
    fix_apt
    upgrade_to_buster
    post_upgrade_check
    
    echo
    log_success "========================================="
    log_success "升级完成！"
    log_success "========================================="
    log_info "建议："
    log_info "1. 检查所有服务是否正常运行"
    log_info "2. 检查网络连接是否正常"
    log_info "3. 重启系统: reboot"
    log_info "4. 重启后可继续升级到Debian 11"
    echo
}

# 执行主函数
main "$@"