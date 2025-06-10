#!/bin/bash

# Debian 11 (Bullseye) 到 Debian 12 (Bookworm) 升级脚本 - 增强版
# 版本: 1.2
# 特别修复了升级后重启卡住的问题

set -e

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
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

log_important() {
    echo -e "${PURPLE}[IMPORTANT]${NC} $(date '+%H:%M:%S') - $1"
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
    if ! grep -q "^11\." /etc/debian_version 2>/dev/null && ! grep -q "bullseye" /etc/debian_version 2>/dev/null; then
        log_error "此脚本仅适用于Debian 11 (Bullseye)"
        log_error "当前版本: $(cat /etc/debian_version)"
        exit 1
    fi
}

# 预升级系统检查
pre_upgrade_check() {
    log_info "执行预升级系统检查..."
    
    # 检查磁盘空间
    local available_space=$(df / | awk 'NR==2 {print $4}')
    if [[ $available_space -lt 4194304 ]]; then  # 4GB
        log_error "根分区可用空间不足4GB，请清理空间后再试"
        exit 1
    fi
    
    # 检查启动分区空间
    if mountpoint -q /boot; then
        local boot_space=$(df /boot | awk 'NR==2 {print $4}')
        if [[ $boot_space -lt 204800 ]]; then  # 200MB
            log_warning "/boot分区空间不足，清理旧内核..."
            apt-get autoremove -y --purge $(dpkg -l | grep '^rc' | awk '{print $2}') 2>/dev/null || true
            apt-get autoremove -y --purge $(dpkg -l | grep linux-image | grep -v $(uname -r) | grep -v linux-image-amd64 | grep -v linux-image-686 | awk '{print $2}' | head -n -2) 2>/dev/null || true
        fi
    fi
    
    # 检查系统架构
    local arch=$(dpkg --print-architecture)
    log_info "系统架构: $arch"
}

# 修复已知的11到12升级问题
fix_bullseye_to_bookworm_issues() {
    log_info "修复Debian 11到12的已知升级问题..."
    
    # 1. 修复systemd相关问题
    log_info "检查systemd配置..."
    # 确保systemd-resolved不会干扰DNS
    if systemctl is-enabled systemd-resolved >/dev/null 2>&1; then
        log_info "配置systemd-resolved..."
        mkdir -p /etc/systemd/resolved.conf.d/
        cat > /etc/systemd/resolved.conf.d/no-stub.conf << EOF
[Resolve]
DNSStubListener=no
EOF
    fi
    
    # 2. 清理可能导致问题的旧配置
    log_info "清理旧配置文件..."
    # 移除过时的网络配置
    if [[ -f /etc/network/interfaces.d/setup ]]; then
        mv /etc/network/interfaces.d/setup /etc/network/interfaces.d/setup.old 2>/dev/null || true
    fi
    
    # 3. 确保关键服务配置正确
    log_info "检查关键服务配置..."
    # 确保getty服务正常
    systemctl enable getty@tty1.service 2>/dev/null || true
    
    # 4. 修复可能的内核模块问题
    log_info "更新内核模块配置..."
    if [[ -f /etc/modules ]]; then
        cp /etc/modules /etc/modules.bak
        # 确保基本模块加载
        for module in "loop" "dm_mod"; do
            if ! grep -q "^$module" /etc/modules; then
                echo "$module" >> /etc/modules
            fi
        done
    fi
    
    # 5. 预先安装重要的过渡包
    log_info "安装过渡包..."
    apt-get update
    DEBIAN_FRONTEND=noninteractive apt-get install -y \
        systemd systemd-sysv systemd-timesyncd \
        2>/dev/null || true
}

# 备份重要文件
backup_files() {
    log_info "备份重要配置文件..."
    local backup_dir="/root/debian_upgrade_backup_$(date +%Y%m%d_%H%M%S)"
    mkdir -p "$backup_dir"
    
    # 备份sources.list
    cp -r /etc/apt/sources.list* "$backup_dir/" 2>/dev/null || true
    
    # 备份重要配置
    for dir in /etc/network /etc/systemd /etc/default /etc/ssh /etc/grub.d /boot/grub /etc/fstab; do
        if [[ -e "$dir" ]]; then
            cp -r "$dir" "$backup_dir/" 2>/dev/null || true
        fi
    done
    
    # 备份内核和引导信息
    cp /boot/config-$(uname -r) "$backup_dir/" 2>/dev/null || true
    dpkg -l | grep -E "(linux-image|grub)" > "$backup_dir/boot_packages.txt"
    
    # 记录当前运行的服务
    systemctl list-units --type=service --state=running > "$backup_dir/running_services.txt"
    
    log_success "备份完成: $backup_dir"
    echo "$backup_dir" > /tmp/debian_upgrade_backup_path
}

# 特别的引导修复函数
fix_boot_issues() {
    log_important "执行引导系统修复（防止重启卡住）..."
    
    # 1. 确保GRUB配置正确
    log_info "更新GRUB配置..."
    if [[ -f /etc/default/grub ]]; then
        cp /etc/default/grub /etc/default/grub.bak
        
        # 确保控制台输出
        sed -i 's/^GRUB_CMDLINE_LINUX_DEFAULT=.*/GRUB_CMDLINE_LINUX_DEFAULT="console=tty0 console=ttyS0,115200"/' /etc/default/grub
        
        # 禁用quiet模式以便看到启动信息
        sed -i 's/quiet//g' /etc/default/grub
        
        # 减少GRUB等待时间
        sed -i 's/^GRUB_TIMEOUT=.*/GRUB_TIMEOUT=5/' /etc/default/grub
    fi
    
    # 2. 重新安装和配置GRUB
    log_info "重新安装GRUB..."
    DEBIAN_FRONTEND=noninteractive apt-get install --reinstall -y grub-pc grub-common
    
    # 检测启动磁盘
    local boot_disk=""
    if [[ -b /dev/sda ]]; then
        boot_disk="/dev/sda"
    elif [[ -b /dev/vda ]]; then
        boot_disk="/dev/vda"
    elif [[ -b /dev/xvda ]]; then
        boot_disk="/dev/xvda"
    fi
    
    if [[ -n "$boot_disk" ]]; then
        log_info "在 $boot_disk 上安装GRUB..."
        grub-install "$boot_disk" || log_warning "GRUB安装警告，继续..."
    fi
    
    # 更新GRUB配置
    update-grub
    
    # 3. 清理并重建initramfs
    log_info "重建initramfs..."
    # 删除旧的initramfs
    find /boot -name "initrd.img-*" ! -name "initrd.img-$(uname -r)*" -mtime +7 -delete 2>/dev/null || true
    
    # 重建所有initramfs
    update-initramfs -u -k all
    
    # 4. 确保必要的服务启用
    log_info "确保引导服务正常..."
    for service in systemd-timesyncd ssh networking; do
        systemctl enable "$service" 2>/dev/null || true
    done
    
    # 5. 创建紧急修复脚本
    log_info "创建紧急修复脚本..."
    cat > /root/emergency_fix.sh << 'EOFIX'
#!/bin/bash
# 紧急修复脚本 - 如果系统无法正常启动时使用

# 修复网络
dhclient -v eth0 2>/dev/null || dhclient -v ens3 2>/dev/null || true

# 修复SSH
service ssh start || service sshd start || true

# 修复系统
apt-get update
apt-get --fix-broken install -y
dpkg --configure -a

echo "紧急修复完成"
EOFIX
    chmod +x /root/emergency_fix.sh
}

# 清理和修复APT
fix_apt() {
    log_info "清理APT缓存和修复依赖..."
    
    # 停止自动更新服务
    for service in apt-daily apt-daily-upgrade unattended-upgrades; do
        systemctl stop "${service}.timer" 2>/dev/null || true
        systemctl stop "${service}" 2>/dev/null || true
        systemctl disable "${service}.timer" 2>/dev/null || true
    done
    
    # 清理锁文件
    rm -f /var/lib/dpkg/lock-frontend
    rm -f /var/lib/dpkg/lock
    rm -f /var/cache/apt/archives/lock
    rm -f /var/lib/apt/lists/lock
    
    # 修复dpkg
    dpkg --configure -a
    
    # 修复依赖
    apt-get --fix-broken install -y
    
    # 清理缓存
    apt-get clean
    apt-get autoclean
}

# 更新到Debian 12
upgrade_to_bookworm() {
    log_info "开始升级到Debian 12 (Bookworm)..."
    
    # 更新当前系统
    log_info "更新当前系统到最新..."
    apt-get update
    DEBIAN_FRONTEND=noninteractive apt-get upgrade -y \
        -o Dpkg::Options::="--force-confdef" \
        -o Dpkg::Options::="--force-confold"
    
    # 安装non-free-firmware相关包（Debian 12新增）
    log_info "准备固件支持..."
    DEBIAN_FRONTEND=noninteractive apt-get install -y \
        firmware-linux-free \
        2>/dev/null || true
    
    # 备份并更新sources.list
    log_info "更新软件源到Bookworm..."
    cp /etc/apt/sources.list /etc/apt/sources.list.bullseye.bak
    
    # Debian 12包含non-free-firmware
    cat > /etc/apt/sources.list << EOF
# Debian 12 (Bookworm)
deb http://deb.debian.org/debian bookworm main contrib non-free non-free-firmware
deb-src http://deb.debian.org/debian bookworm main contrib non-free non-free-firmware

# Security updates
deb http://deb.debian.org/debian-security bookworm-security main contrib non-free non-free-firmware
deb-src http://deb.debian.org/debian-security bookworm-security main contrib non-free non-free-firmware

# Updates
deb http://deb.debian.org/debian bookworm-updates main contrib non-free non-free-firmware
deb-src http://deb.debian.org/debian bookworm-updates main contrib non-free non-free-firmware
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
        -o Dpkg::Options::="--force-confold" \
        --without-new-pkgs
    
    # 预先处理关键包
    log_info "升级关键系统包..."
    DEBIAN_FRONTEND=noninteractive apt-get install -y \
        base-files base-passwd bash \
        -o Dpkg::Options::="--force-confdef" \
        -o Dpkg::Options::="--force-confold"
    
    # 安装新内核
    log_info "安装Debian 12内核..."
    local kernel_pkg="linux-image-amd64"
    if [[ $(dpkg --print-architecture) == "i386" ]]; then
        kernel_pkg="linux-image-686"
    fi
    
    DEBIAN_FRONTEND=noninteractive apt-get install -y \
        "$kernel_pkg" linux-headers-"${kernel_pkg#linux-image-}" \
        -o Dpkg::Options::="--force-confdef" \
        -o Dpkg::Options::="--force-confold"
    
    # 执行完整升级
    log_info "执行完整系统升级（请耐心等待）..."
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
    
    # 再次修复引导问题
    fix_boot_issues
    
    # 检查并修复网络配置
    log_info "检查网络配置..."
    if [[ -f /etc/network/interfaces ]]; then
        # 确保lo接口配置存在
        if ! grep -q "^auto lo" /etc/network/interfaces; then
            cat >> /etc/network/interfaces << EOF

auto lo
iface lo inet loopback
EOF
        fi
    fi
    
    # 确保网络服务正常
    systemctl enable systemd-networkd 2>/dev/null || true
    systemctl enable networking 2>/dev/null || true
    
    # 检查SSH配置
    log_info "验证SSH配置..."
    if [[ -f /etc/ssh/sshd_config ]]; then
        # 确保SSH监听正确
        if ! grep -q "^Port" /etc/ssh/sshd_config; then
            echo "Port 22" >> /etc/ssh/sshd_config
        fi
        
        # 测试SSH配置
        sshd -t || {
            log_warning "SSH配置有误，使用默认配置..."
            cp /etc/ssh/sshd_config /etc/ssh/sshd_config.broken
            apt-get install --reinstall -y openssh-server
        }
        
        systemctl restart ssh || systemctl restart sshd
    fi
    
    # 清理并重建包数据库
    log_info "更新包数据库..."
    apt-get update
    
    # 确保所有服务正常启动
    systemctl daemon-reload
    
    # 创建系统状态报告
    log_info "生成系统状态报告..."
    {
        echo "=== Debian 12 升级报告 ==="
        echo "升级时间: $(date)"
        echo "系统版本: $(cat /etc/debian_version)"
        echo "内核版本: $(uname -r)"
        echo ""
        echo "=== 磁盘使用 ==="
        df -h
        echo ""
        echo "=== 内存使用 ==="
        free -h
        echo ""
        echo "=== 运行的服务 ==="
        systemctl list-units --type=service --state=running
    } > /root/debian12_upgrade_report.txt
    
    # 验证版本
    local new_version=$(cat /etc/debian_version)
    if [[ "$new_version" =~ ^12\. ]] || [[ "$new_version" =~ bookworm ]]; then
        log_success "升级成功！当前版本: Debian 12 (Bookworm)"
    else
        log_warning "升级可能未完成，请检查系统版本: $new_version"
    fi
}

# 主函数
main() {
    echo "========================================="
    echo "Debian 11 → 12 升级脚本（修复重启问题）"
    echo "========================================="
    
    check_root
    check_version
    pre_upgrade_check
    
    echo
    log_warning "⚠️  重要提醒："
    log_warning "1. 此脚本专门修复了升级后重启卡住的问题"
    log_warning "2. 升级过程会自动配置引导系统"
    log_warning "3. 请确保有VPS控制台访问权限"
    log_warning "4. 升级时间约30-60分钟"
    echo
    
    read -p "是否开始升级到Debian 12? [y/N]: " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        log_info "升级已取消"
        exit 0
    fi
    
    # 执行升级步骤
    fix_bullseye_to_bookworm_issues
    backup_files
    fix_apt
    upgrade_to_bookworm
    post_upgrade_check
    
    echo
    log_success "========================================="
    log_success "升级完成！"
    log_success "========================================="
    echo
    log_important "🔧 重要操作提醒："
    echo
    log_info "1. 立即测试（在重启前）："
    log_info "   - 打开新的SSH连接测试"
    log_info "   - 运行: systemctl status ssh"
    log_info "   - 运行: ip addr show"
    echo
    log_info "2. 查看升级报告："
    log_info "   cat /root/debian12_upgrade_report.txt"
    echo
    log_info "3. 如果一切正常，重启系统："
    log_info "   reboot"
    echo
    log_warning "⚠️  如果重启后无法连接："
    log_warning "1. 使用VPS控制台访问"
    log_warning "2. 运行: /root/emergency_fix.sh"
    log_warning "3. 备份位置: $(cat /tmp/debian_upgrade_backup_path 2>/dev/null)"
    echo
    
    # 最后的检查
    read -p "是否现在检查系统状态? [Y/n]: " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Nn]$ ]]; then
        echo
        log_info "=== 系统状态检查 ==="
        systemctl status ssh --no-pager || systemctl status sshd --no-pager || true
        echo
        log_info "=== 网络配置 ==="
        ip addr show
        echo
        log_info "=== 引导配置 ==="
        grep -E "^GRUB_CMDLINE_LINUX|^GRUB_TIMEOUT" /etc/default/grub
        echo
    fi
}

# 执行主函数
main "$@"