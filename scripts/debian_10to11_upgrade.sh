#!/bin/bash

# Debian 10 (Buster) 到 Debian 11 (Bullseye) 升级脚本 - 增强版
# 版本: 1.1
# 特别针对VPS环境和常见问题进行了优化

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
    if ! grep -q "^10\." /etc/debian_version 2>/dev/null && ! grep -q "buster" /etc/debian_version 2>/dev/null; then
        log_error "此脚本仅适用于Debian 10 (Buster)"
        log_error "当前版本: $(cat /etc/debian_version)"
        exit 1
    fi
}

# 预升级系统检查
pre_upgrade_check() {
    log_info "执行预升级系统检查..."
    
    # 检查磁盘空间
    local available_space=$(df / | awk 'NR==2 {print $4}')
    if [[ $available_space -lt 3145728 ]]; then  # 3GB
        log_error "根分区可用空间不足3GB，请清理空间后再试"
        exit 1
    fi
    
    # 检查内存
    local available_memory=$(free -m | awk 'NR==2{printf "%.0f", $7}')
    if [[ $available_memory -lt 256 ]]; then
        log_warning "可用内存不足256MB，升级可能会很慢"
        read -p "是否继续? [y/N]: " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            exit 1
        fi
    fi
    
    # 检查网络连接
    if ! ping -c 1 deb.debian.org >/dev/null 2>&1; then
        log_warning "无法连接到Debian官方源"
        log_info "尝试使用镜像源..."
    fi
}

# 修复已知的10到11升级问题
fix_buster_to_bullseye_issues() {
    log_info "修复Debian 10到11的已知升级问题..."
    
    # 1. 修复usrmerge问题
    log_info "检查并安装usrmerge..."
    if ! dpkg -l | grep -q "^ii.*usrmerge"; then
        apt-get update
        DEBIAN_FRONTEND=noninteractive apt-get install -y usrmerge || {
            log_warning "usrmerge安装失败，尝试手动修复..."
            # 手动创建符号链接
            for dir in bin sbin lib lib32 lib64 libx32; do
                if [[ -d "/$dir" ]] && [[ ! -L "/$dir" ]]; then
                    log_info "移动 /$dir 到 /usr/$dir"
                    if [[ -d "/usr/$dir" ]]; then
                        cp -a "/$dir"/* "/usr/$dir"/ 2>/dev/null || true
                    else
                        mv "/$dir" "/usr/$dir"
                    fi
                    ln -s "usr/$dir" "/$dir"
                fi
            done
        }
    fi
    
    # 2. 修复locale问题
    log_info "修复locale设置..."
    if ! locale -a | grep -q "en_US.utf8"; then
        echo "en_US.UTF-8 UTF-8" >> /etc/locale.gen
        locale-gen
    fi
    export LANG=en_US.UTF-8
    export LC_ALL=en_US.UTF-8
    
    # 3. 更新ca-certificates
    log_info "更新证书..."
    apt-get update
    apt-get install -y ca-certificates
    update-ca-certificates
    
    # 4. 修复可能的Python问题
    log_info "检查Python配置..."
    if command -v python3 >/dev/null 2>&1; then
        update-alternatives --install /usr/bin/python python /usr/bin/python3 1 2>/dev/null || true
    fi
    
    # 5. 清理残留配置
    log_info "清理残留配置..."
    apt-get purge -y $(dpkg -l | grep '^rc' | awk '{print $2}') 2>/dev/null || true
}

# 备份重要文件
backup_files() {
    log_info "备份重要配置文件..."
    local backup_dir="/root/debian_upgrade_backup_$(date +%Y%m%d_%H%M%S)"
    mkdir -p "$backup_dir"
    
    # 备份sources.list
    cp -r /etc/apt/sources.list* "$backup_dir/" 2>/dev/null || true
    
    # 备份重要配置
    for dir in /etc/network /etc/systemd /etc/default /etc/ssh /etc/grub.d /boot/grub; do
        if [[ -d "$dir" ]]; then
            cp -r "$dir" "$backup_dir/" 2>/dev/null || true
        fi
    done
    
    # 备份已安装包列表
    dpkg --get-selections > "$backup_dir/package_list.txt"
    
    # 备份内核列表
    dpkg -l | grep linux-image > "$backup_dir/kernel_list.txt" 2>/dev/null || true
    
    log_success "备份完成: $backup_dir"
    echo "$backup_dir" > /tmp/debian_upgrade_backup_path
}

# 清理和修复APT
fix_apt() {
    log_info "清理APT缓存和修复依赖..."
    
    # 停止自动更新服务
    for service in apt-daily apt-daily-upgrade unattended-upgrades; do
        systemctl stop "${service}.timer" 2>/dev/null || true
        systemctl stop "${service}" 2>/dev/null || true
    done
    
    # 等待APT锁释放
    local count=0
    while fuser /var/lib/dpkg/lock-frontend >/dev/null 2>&1; do
        log_info "等待其他APT进程完成..."
        sleep 2
        count=$((count + 1))
        if [[ $count -gt 30 ]]; then
            log_warning "强制清理APT锁..."
            pkill -9 apt 2>/dev/null || true
            pkill -9 dpkg 2>/dev/null || true
            break
        fi
    done
    
    # 清理锁文件
    rm -f /var/lib/dpkg/lock-frontend 2>/dev/null || true
    rm -f /var/lib/dpkg/lock 2>/dev/null || true
    rm -f /var/cache/apt/archives/lock 2>/dev/null || true
    rm -f /var/lib/apt/lists/lock 2>/dev/null || true
    
    # 修复dpkg
    dpkg --configure -a 2>/dev/null || true
    
    # 修复依赖
    apt-get --fix-broken install -y 2>/dev/null || true
    
    # 清理缓存
    apt-get clean
    apt-get autoclean
}

# 更新到Debian 11
upgrade_to_bullseye() {
    log_info "开始升级到Debian 11 (Bullseye)..."
    
    # 更新当前系统
    log_info "更新当前系统到最新..."
    apt-get update || {
        log_warning "更新失败，尝试修复..."
        rm -rf /var/lib/apt/lists/*
        apt-get update
    }
    
    DEBIAN_FRONTEND=noninteractive apt-get upgrade -y \
        -o Dpkg::Options::="--force-confdef" \
        -o Dpkg::Options::="--force-confold"
    
    DEBIAN_FRONTEND=noninteractive apt-get dist-upgrade -y \
        -o Dpkg::Options::="--force-confdef" \
        -o Dpkg::Options::="--force-confold"
    
    # 安装必要的过渡包
    log_info "安装过渡包..."
    DEBIAN_FRONTEND=noninteractive apt-get install -y \
        gcc-8-base libgcc-s1 libc6 libcrypt1 \
        2>/dev/null || true
    
    # 备份并更新sources.list
    log_info "更新软件源到Bullseye..."
    cp /etc/apt/sources.list /etc/apt/sources.list.buster.bak
    
    # 使用新的安全源格式
    cat > /etc/apt/sources.list << EOF
# Debian 11 (Bullseye)
deb http://deb.debian.org/debian bullseye main contrib non-free
deb-src http://deb.debian.org/debian bullseye main contrib non-free

# Security updates - 注意：Debian 11使用新格式
deb http://deb.debian.org/debian-security bullseye-security main contrib non-free
deb-src http://deb.debian.org/debian-security bullseye-security main contrib non-free

# Updates
deb http://deb.debian.org/debian bullseye-updates main contrib non-free
deb-src http://deb.debian.org/debian bullseye-updates main contrib non-free
EOF

    # 清理第三方源
    if [[ -d /etc/apt/sources.list.d ]]; then
        log_info "临时禁用第三方源..."
        mkdir -p /etc/apt/sources.list.d.bak
        mv /etc/apt/sources.list.d/*.list /etc/apt/sources.list.d.bak/ 2>/dev/null || true
    fi
    
    # 更新软件包列表
    log_info "更新软件包列表..."
    apt-get update || {
        log_error "无法更新软件包列表，请检查网络连接"
        exit 1
    }
    
    # 执行最小升级
    log_info "执行最小系统升级..."
    DEBIAN_FRONTEND=noninteractive apt-get upgrade -y \
        -o Dpkg::Options::="--force-confdef" \
        -o Dpkg::Options::="--force-confold" \
        --without-new-pkgs
    
    # 安装新内核（分步骤）
    log_info "准备安装新内核..."
    
    # 先更新内核依赖
    DEBIAN_FRONTEND=noninteractive apt-get install -y \
        linux-base linux-image-amd64 \
        -o Dpkg::Options::="--force-confdef" \
        -o Dpkg::Options::="--force-confold" || {
        log_warning "AMD64内核安装失败，尝试686内核..."
        DEBIAN_FRONTEND=noninteractive apt-get install -y \
            linux-base linux-image-686 \
            -o Dpkg::Options::="--force-confdef" \
            -o Dpkg::Options::="--force-confold"
    }
    
    # 执行完整升级
    log_info "执行完整系统升级（这可能需要较长时间）..."
    DEBIAN_FRONTEND=noninteractive apt-get dist-upgrade -y \
        -o Dpkg::Options::="--force-confdef" \
        -o Dpkg::Options::="--force-confold" || {
        log_warning "完整升级遇到问题，尝试修复..."
        apt-get --fix-broken install -y
        DEBIAN_FRONTEND=noninteractive apt-get dist-upgrade -y \
            -o Dpkg::Options::="--force-confdef" \
            -o Dpkg::Options::="--force-confold"
    }
    
    # 清理旧包
    log_info "清理系统..."
    apt-get autoremove -y --purge
    apt-get autoclean
}

# 升级后检查和修复
post_upgrade_check() {
    log_info "执行升级后检查和修复..."
    
    # 确保GRUB正确安装和配置
    log_info "检查并更新GRUB..."
    if [[ -d /boot/grub ]]; then
        # 确保GRUB包已安装
        if ! dpkg -l | grep -q "^ii.*grub-pc"; then
            log_info "安装GRUB..."
            DEBIAN_FRONTEND=noninteractive apt-get install -y grub-pc
        fi
        
        # 更新GRUB配置
        update-grub || {
            log_warning "GRUB更新失败，尝试重新安装..."
            grub-install /dev/sda 2>/dev/null || grub-install /dev/vda 2>/dev/null || true
            update-grub
        }
    fi
    
    # 重新生成initramfs
    log_info "更新initramfs..."
    update-initramfs -u -k all || {
        log_warning "initramfs更新失败，尝试修复..."
        # 清理旧的initramfs
        find /boot -name "initrd.img-*" -mtime +30 -delete 2>/dev/null || true
        update-initramfs -u
    }
    
    # 检查并修复网络配置
    log_info "检查网络配置..."
    # 确保网络管理服务正常
    if systemctl is-enabled NetworkManager >/dev/null 2>&1; then
        systemctl restart NetworkManager
    elif systemctl is-enabled networking >/dev/null 2>&1; then
        systemctl restart networking
    fi
    
    # 检查SSH配置
    if [[ -f /etc/ssh/sshd_config ]]; then
        log_info "检查SSH配置..."
        # 备份SSH配置
        cp /etc/ssh/sshd_config /etc/ssh/sshd_config.bak.$(date +%s)
        
        # 确保SSH正常工作
        systemctl restart ssh || systemctl restart sshd || true
    fi
    
    # 清理并重建包数据库
    log_info "重建包数据库..."
    apt-get update
    
    # 检查系统服务
    log_info "检查关键系统服务..."
    systemctl daemon-reload
    
    # 验证版本
    local new_version=$(cat /etc/debian_version)
    if [[ "$new_version" =~ ^11\. ]] || [[ "$new_version" =~ bullseye ]]; then
        log_success "升级成功！当前版本: Debian 11 (Bullseye)"
    else
        log_warning "升级可能未完成，请检查系统版本: $new_version"
    fi
    
    # 显示内核信息
    log_info "当前内核: $(uname -r)"
    log_info "可用内核:"
    dpkg -l | grep linux-image | grep ^ii
}

# 主函数
main() {
    echo "========================================="
    echo "Debian 10 → 11 升级脚本（增强版）"
    echo "========================================="
    
    check_root
    check_version
    pre_upgrade_check
    
    echo
    log_warning "升级建议："
    log_warning "1. 确保已备份重要数据"
    log_warning "2. 确保有控制台访问权限（VPS用户）"
    log_warning "3. 升级过程可能需要30-60分钟"
    echo
    
    read -p "是否开始升级到Debian 11? [y/N]: " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        log_info "升级已取消"
        exit 0
    fi
    
    # 执行升级步骤
    fix_buster_to_bullseye_issues
    backup_files
    fix_apt
    upgrade_to_bullseye
    post_upgrade_check
    
    echo
    log_success "========================================="
    log_success "升级完成！"
    log_success "========================================="
    log_info "重要提醒："
    log_info "1. 检查所有服务是否正常运行"
    log_info "2. 测试SSH连接（保持当前会话）"
    log_info "3. 检查网络配置是否正常"
    log_info "4. 建议重启系统: reboot"
    log_info "5. 如遇问题，备份位置: $(cat /tmp/debian_upgrade_backup_path 2>/dev/null || echo '请查看脚本输出')"
    echo
    log_warning "⚠️  重启前请确保："
    log_warning "- SSH服务正常运行"
    log_warning "- 网络配置正确"
    log_warning "- GRUB配置已更新"
    echo
}

# 执行主函数
main "$@"