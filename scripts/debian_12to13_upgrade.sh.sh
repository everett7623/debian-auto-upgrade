#!/bin/bash

# Debian 12 (Bookworm) 到 Debian 13 (Trixie) 升级脚本
# 版本: 1.0
# 注意：Debian 13是测试版本，不建议在生产环境使用

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
    if ! grep -q "^12\." /etc/debian_version 2>/dev/null && ! grep -q "bookworm" /etc/debian_version 2>/dev/null; then
        log_error "此脚本仅适用于Debian 12 (Bookworm)"
        log_error "当前版本: $(cat /etc/debian_version)"
        exit 1
    fi
}

# 显示测试版本警告
show_testing_warning() {
    echo
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    log_warning "⚠️  重要警告：Debian 13 (Trixie) 是测试版本！"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo
    log_important "请仔细阅读以下信息："
    echo
    echo "📋 版本状态："
    echo "   • Debian 13 (Trixie) - Testing/测试版"
    echo "   • 非稳定版本，持续更新中"
    echo "   • 可能包含未修复的bug"
    echo
    echo "⚠️  风险说明："
    echo "   • 软件包可能频繁更新"
    echo "   • 可能出现依赖冲突"
    echo "   • 系统可能不稳定"
    echo "   • 不适合生产环境"
    echo
    echo "✅ 适用场景："
    echo "   • 开发测试环境"
    echo "   • 需要最新软件包"
    echo "   • 能够处理系统问题"
    echo
    echo "❌ 不适用场景："
    echo "   • 生产服务器"
    echo "   • 重要业务系统"
    echo "   • 需要稳定性的环境"
    echo
    echo "💡 建议："
    echo "   保持使用Debian 12 (Bookworm)稳定版"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo
}

# 用户确认
get_user_confirmation() {
    local response=""
    
    while true; do
        echo -n "⚠️  您确定要升级到测试版本吗？请输入 'I UNDERSTAND THE RISKS' 确认: "
        read -r response
        
        if [[ "$response" == "I UNDERSTAND THE RISKS" ]]; then
            return 0
        elif [[ "$response" == "no" ]] || [[ "$response" == "n" ]]; then
            return 1
        else
            echo "❌ 请准确输入 'I UNDERSTAND THE RISKS' 或输入 'no' 取消"
        fi
    done
}

# 预升级系统检查
pre_upgrade_check() {
    log_info "执行预升级系统检查..."
    
    # 检查磁盘空间
    local available_space=$(df / | awk 'NR==2 {print $4}')
    if [[ $available_space -lt 5242880 ]]; then  # 5GB
        log_error "根分区可用空间不足5GB，测试版本需要更多空间"
        exit 1
    fi
    
    # 检查当前系统是否完全更新
    log_info "检查系统更新状态..."
    apt-get update
    if [[ $(apt-get -s upgrade | grep -c "^Inst") -gt 0 ]]; then
        log_warning "当前系统有待更新的软件包"
        log_info "先更新当前系统..."
        DEBIAN_FRONTEND=noninteractive apt-get upgrade -y
    fi
}

# 备份重要文件
backup_files() {
    log_info "备份重要配置文件..."
    local backup_dir="/root/debian_upgrade_backup_$(date +%Y%m%d_%H%M%S)"
    mkdir -p "$backup_dir"
    
    # 备份sources.list
    cp -r /etc/apt/sources.list* "$backup_dir/" 2>/dev/null || true
    
    # 备份APT配置
    cp -r /etc/apt/preferences* "$backup_dir/" 2>/dev/null || true
    cp -r /etc/apt/apt.conf* "$backup_dir/" 2>/dev/null || true
    
    # 备份重要配置
    for dir in /etc/network /etc/systemd /etc/default /etc/ssh /etc/grub.d /boot/grub; do
        if [[ -d "$dir" ]]; then
            cp -r "$dir" "$backup_dir/" 2>/dev/null || true
        fi
    done
    
    # 备份已安装包列表
    dpkg --get-selections > "$backup_dir/package_list.txt"
    apt-mark showmanual > "$backup_dir/manual_packages.txt"
    
    # 创建回滚脚本
    cat > "$backup_dir/rollback.sh" << 'EOROLLBACK'
#!/bin/bash
# 回滚到Debian 12脚本

echo "开始回滚到Debian 12..."

# 恢复sources.list
cp /etc/apt/sources.list.bookworm.bak /etc/apt/sources.list

# 恢复第三方源
if [[ -d /etc/apt/sources.list.d.bak ]]; then
    rm -rf /etc/apt/sources.list.d
    mv /etc/apt/sources.list.d.bak /etc/apt/sources.list.d
fi

# 更新并降级
apt-get update
apt-get install -y --allow-downgrades base-files=12*

echo "请手动检查并修复系统"
EOROLLBACK
    chmod +x "$backup_dir/rollback.sh"
    
    log_success "备份完成: $backup_dir"
    echo "$backup_dir" > /tmp/debian_upgrade_backup_path
}

# 配置APT优先级
configure_apt_preferences() {
    log_info "配置APT优先级..."
    
    # 创建preferences文件以控制升级
    cat > /etc/apt/preferences.d/debian-testing << EOF
# 默认使用testing
Package: *
Pin: release a=testing
Pin-Priority: 500

# 防止意外升级到unstable
Package: *
Pin: release a=unstable
Pin-Priority: 100
EOF
}

# 清理和修复APT
fix_apt() {
    log_info "清理APT缓存和修复依赖..."
    
    # 停止自动更新
    for service in apt-daily apt-daily-upgrade unattended-upgrades; do
        systemctl stop "${service}.timer" 2>/dev/null || true
        systemctl stop "${service}" 2>/dev/null || true
        systemctl disable "${service}.timer" 2>/dev/null || true
    done
    
    # 清理
    rm -f /var/lib/dpkg/lock-frontend
    rm -f /var/lib/dpkg/lock
    rm -f /var/cache/apt/archives/lock
    
    dpkg --configure -a
    apt-get --fix-broken install -y
    apt-get clean
}

# 更新到Debian 13
upgrade_to_trixie() {
    log_info "开始升级到Debian 13 (Trixie)..."
    
    # 备份并更新sources.list
    log_info "更新软件源到Trixie..."
    cp /etc/apt/sources.list /etc/apt/sources.list.bookworm.bak
    
    cat > /etc/apt/sources.list << EOF
# Debian 13 (Trixie) - Testing
deb http://deb.debian.org/debian trixie main contrib non-free non-free-firmware
deb-src http://deb.debian.org/debian trixie main contrib non-free non-free-firmware

# Security updates for testing
deb http://deb.debian.org/debian-security trixie-security main contrib non-free non-free-firmware
deb-src http://deb.debian.org/debian-security trixie-security main contrib non-free non-free-firmware

# No separate updates repository for testing
# Updates are directly pushed to the testing repository
EOF

    # 禁用第三方源
    if [[ -d /etc/apt/sources.list.d ]]; then
        log_info "临时禁用第三方源..."
        mkdir -p /etc/apt/sources.list.d.bak
        mv /etc/apt/sources.list.d/*.list /etc/apt/sources.list.d.bak/ 2>/dev/null || true
    fi
    
    # 配置APT优先级
    configure_apt_preferences
    
    # 更新软件包列表
    log_info "更新软件包列表..."
    apt-get update || {
        log_error "无法更新软件包列表"
        log_info "可能是因为Trixie仓库还未完全就绪"
        exit 1
    }
    
    # 执行最小升级
    log_info "执行最小系统升级..."
    DEBIAN_FRONTEND=noninteractive apt-get upgrade -y \
        -o Dpkg::Options::="--force-confdef" \
        -o Dpkg::Options::="--force-confold" \
        --without-new-pkgs || {
        log_warning "最小升级遇到问题，尝试修复..."
        apt-get --fix-broken install -y
    }
    
    # 安装新的base-files
    log_info "升级核心系统文件..."
    DEBIAN_FRONTEND=noninteractive apt-get install -y \
        base-files apt dpkg \
        -o Dpkg::Options::="--force-confdef" \
        -o Dpkg::Options::="--force-confold"
    
    # 执行完整升级
    log_info "执行完整系统升级（测试版本包较多，请耐心等待）..."
    DEBIAN_FRONTEND=noninteractive apt-get dist-upgrade -y \
        -o Dpkg::Options::="--force-confdef" \
        -o Dpkg::Options::="--force-confold" || {
        log_warning "升级过程中出现问题，尝试继续..."
        apt-get --fix-broken install -y
        DEBIAN_FRONTEND=noninteractive apt-get dist-upgrade -y \
            -o Dpkg::Options::="--force-confdef" \
            -o Dpkg::Options::="--force-confold"
    }
    
    # 清理系统
    log_info "清理系统..."
    apt-get autoremove -y --purge
    apt-get autoclean
}

# 测试版本特殊处理
handle_testing_specific() {
    log_info "处理测试版本特定配置..."
    
    # 1. 配置自动更新策略（测试版本不建议自动更新）
    log_info "禁用自动更新（测试版本）..."
    cat > /etc/apt/apt.conf.d/20auto-upgrades << EOF
APT::Periodic::Update-Package-Lists "0";
APT::Periodic::Unattended-Upgrade "0";
APT::Periodic::AutocleanInterval "7";
EOF
    
    # 2. 安装apt-listbugs（帮助跟踪bug）
    log_info "安装bug跟踪工具..."
    DEBIAN_FRONTEND=noninteractive apt-get install -y apt-listbugs || true
    
    # 3. 创建测试版本管理脚本
    cat > /usr/local/bin/debian-testing-update << 'EOSCRIPT'
#!/bin/bash
# Debian Testing更新脚本

echo "=== Debian Testing 更新脚本 ==="
echo "检查更新前的重要bug..."

# 更新包列表
apt-get update

# 显示将要更新的包
echo "将要更新的软件包："
apt list --upgradable

# 询问是否继续
read -p "是否继续更新? [y/N]: " -n 1 -r
echo
if [[ $REPLY =~ ^[Yy]$ ]]; then
    apt-get upgrade -y
    apt-get dist-upgrade -y
else
    echo "更新已取消"
fi
EOSCRIPT
    chmod +x /usr/local/bin/debian-testing-update
    
    # 4. 创建状态检查脚本
    cat > /usr/local/bin/debian-testing-status << 'EOSCRIPT'
#!/bin/bash
# Debian Testing状态检查

echo "=== Debian Testing 系统状态 ==="
echo "版本: $(cat /etc/debian_version)"
echo "代号: $(lsb_release -cs 2>/dev/null || echo 'trixie')"
echo
echo "=== 包统计 ==="
echo "已安装包: $(dpkg -l | grep -c '^ii')"
echo "可升级包: $(apt list --upgradable 2>/dev/null | grep -c upgradable || echo 0)"
echo
echo "=== 存储库状态 ==="
apt-cache policy
EOSCRIPT
    chmod +x /usr/local/bin/debian-testing-status
}

# 升级后检查
post_upgrade_check() {
    log_info "执行升级后检查..."
    
    # 更新GRUB
    if command -v update-grub >/dev/null 2>&1; then
        log_info "更新GRUB配置..."
        update-grub
    fi
    
    # 更新initramfs
    if command -v update-initramfs >/dev/null 2>&1; then
        log_info "更新initramfs..."
        update-initramfs -u -k all
    fi
    
    # 处理测试版本特定设置
    handle_testing_specific
    
    # 重新加载systemd
    systemctl daemon-reload
    
    # 生成升级报告
    log_info "生成升级报告..."
    {
        echo "=== Debian 13 (Testing) 升级报告 ==="
        echo "升级时间: $(date)"
        echo "系统版本: $(cat /etc/debian_version)"
        echo "代号: trixie (testing)"
        echo "内核: $(uname -r)"
        echo ""
        echo "=== 重要提醒 ==="
        echo "1. 您现在运行的是测试版本"
        echo "2. 系统会持续接收更新"
        echo "3. 可能遇到包依赖问题"
        echo "4. 使用 debian-testing-update 手动更新"
        echo "5. 使用 debian-testing-status 检查状态"
        echo ""
        echo "=== 回滚信息 ==="
        echo "如需回滚到Debian 12，使用："
        echo "$(cat /tmp/debian_upgrade_backup_path)/rollback.sh"
    } > /root/debian13_upgrade_report.txt
    
    # 验证版本
    local new_version=$(cat /etc/debian_version)
    if [[ "$new_version" =~ trixie ]] || [[ "$new_version" =~ ^13\. ]]; then
        log_success "升级成功！当前版本: Debian 13 (Trixie/Testing)"
    else
        log_info "当前版本: $new_version"
        log_info "注意：测试版本的版本号可能显示为 'trixie/sid'"
    fi
}

# 主函数
main() {
    echo "========================================="
    echo "Debian 12 → 13 (Testing) 升级脚本"
    echo "========================================="
    
    check_root
    check_version
    
    # 显示警告
    show_testing_warning
    
    # 用户确认
    if ! get_user_confirmation; then
        log_success "明智的选择！保持使用稳定版本。"
        exit 0
    fi
    
    echo
    log_important "您已确认了解风险，开始准备升级..."
    sleep 3
    
    # 执行升级
    pre_upgrade_check
    backup_files
    fix_apt
    upgrade_to_trixie
    post_upgrade_check
    
    echo
    log_success "========================================="
    log_success "升级到测试版本完成！"
    log_success "========================================="
    echo
    log_important "⚠️  测试版本使用指南："
    echo
    echo "1. 📋 查看升级报告："
    echo "   cat /root/debian13_upgrade_report.txt"
    echo
    echo "2. 🔄 手动更新系统（推荐）："
    echo "   debian-testing-update"
    echo
    echo "3. 📊 检查系统状态："
    echo "   debian-testing-status"
    echo
    echo "4. ⚙️  处理问题："
    echo "   - 依赖问题: apt-get -f install"
    echo "   - 包冲突: aptitude (更智能的解决方案)"
    echo
    echo "5. 🔙 如需回滚："
    echo "   $(cat /tmp/debian_upgrade_backup_path 2>/dev/null)/rollback.sh"
    echo
    log_warning "记住：测试版本会频繁更新，建议定期检查并手动更新！"
    echo
}

# 执行主函数
main "$@"