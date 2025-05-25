#!/bin/bash

# Debian自动逐级升级脚本 - 修复版
# 功能：自动检测当前版本并升级到下一个版本，直到最新版本
# 适用于大部分Debian系统，包括VPS环境

set -e  # 遇到错误立即退出

# 脚本版本
SCRIPT_VERSION="2.1"

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

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

log_debug() {
    if [[ "${DEBUG:-}" == "1" ]]; then
        echo -e "${PURPLE}[DEBUG]${NC} $(date '+%H:%M:%S') - $1"
    fi
}

# 用户输入确认函数
get_user_confirmation() {
    local prompt="$1"
    local response=""
    
    # 确保从终端读取输入
    if [[ ! -t 0 ]]; then
        exec 0</dev/tty
    fi
    
    while true; do
        echo -n "$prompt"
        read -r response </dev/tty
        
        case "$response" in
            [Yy][Ee][Ss])
                return 0  # 确认升级
                ;;
            [Nn][Oo]|"")
                return 1  # 取消升级
                ;;
            *)
                echo "❌ 请输入 'YES' (大写) 确认升级到测试版本，或 'no' 取消"
                ;;
        esac
    done
}

# 检查系统环境
check_system() {
    log_info "检查系统环境..."
    
    # 检查是否为Debian系统
    if ! grep -q "^ID=debian" /etc/os-release 2>/dev/null; then
        log_error "此脚本仅适用于Debian系统"
        exit 1
    fi
    
    # 检查网络连接
    if ! ping -c 1 deb.debian.org >/dev/null 2>&1; then
        log_warning "无法连接到Debian官方源，可能需要配置网络或使用镜像源"
    fi
    
    # 检查磁盘空间
    local available_space=$(df / | awk 'NR==2 {print $4}')
    if [[ $available_space -lt 2097152 ]]; then  # 2GB
        log_warning "根分区可用空间不足2GB，升级过程中可能出现空间不足"
    fi
    
    # 检查内存
    local available_memory=$(free -m | awk 'NR==2{printf "%.0f", $7}')
    if [[ $available_memory -lt 512 ]]; then
        log_warning "可用内存不足512MB，升级过程可能较慢"
    fi
    
    log_success "系统环境检查完成"
}

# 检查是否为root用户
check_root() {
    if [[ $EUID -eq 0 ]]; then
        log_warning "检测到以root用户运行，这不是推荐做法"
        if [[ "${FORCE:-}" != "1" ]]; then
            read -p "是否继续？[y/N]: " -n 1 -r </dev/tty
            echo
            if [[ ! $REPLY =~ ^[Yy]$ ]]; then
                log_info "建议使用普通用户配合sudo运行此脚本"
                exit 1
            fi
        fi
        USE_SUDO=""
    else
        if ! sudo -n true 2>/dev/null; then
            log_info "需要sudo权限来执行升级操作"
            sudo -v
        fi
        USE_SUDO="sudo"
    fi
}

# 获取当前Debian版本
get_current_version() {
    local version_id=""
    
    # 尝试从os-release获取版本
    if [[ -f /etc/os-release ]]; then
        version_id=$(grep "^VERSION_ID=" /etc/os-release | cut -d'"' -f2)
    fi
    
    # 如果os-release没有VERSION_ID，尝试从debian_version推断
    if [[ -z "$version_id" && -f /etc/debian_version ]]; then
        local debian_version=$(cat /etc/debian_version)
        case "$debian_version" in
            "8."*) version_id="8" ;;
            "9."*) version_id="9" ;;
            "10."*) version_id="10" ;;
            "11."*) version_id="11" ;;
            "12."*) version_id="12" ;;
            "13."*|"trixie"*) version_id="13" ;;
            "14."*|"forky"*) version_id="14" ;;
        esac
    fi
    
    if [[ -z "$version_id" ]]; then
        log_error "无法确定Debian版本"
        exit 1
    fi
    
    echo "$version_id"
}

# 获取版本代号和状态
get_version_info() {
    case $1 in
        "8") echo "jessie|oldoldstable" ;;
        "9") echo "stretch|oldoldstable" ;;
        "10") echo "buster|oldstable" ;;
        "11") echo "bullseye|oldstable" ;;
        "12") echo "bookworm|stable" ;;
        "13") echo "trixie|testing" ;;
        "14") echo "forky|unstable" ;;
        *) echo "unknown|unknown" ;;
    esac
}

# 获取下一个版本
get_next_version() {
    case $1 in
        "8") echo "9" ;;
        "9") echo "10" ;;
        "10") echo "11" ;;
        "11") echo "12" ;;
        "12") 
            if [[ "${STABLE_ONLY:-}" == "1" ]]; then
                echo ""  # 如果设置了只升级稳定版，不升级到13
            else
                echo "13"
            fi
            ;;
        "13") echo "14" ;;
        *) echo "" ;;
    esac
}

# 检测VPS环境
detect_vps_environment() {
    local vps_type=""
    
    # 检测常见VPS环境
    if [[ -f /proc/vz/version ]]; then
        vps_type="OpenVZ"
    elif [[ -d /proc/xen ]]; then
        vps_type="Xen"
    elif grep -q "VMware" /proc/scsi/scsi 2>/dev/null; then
        vps_type="VMware"
    elif grep -q "QEMU" /proc/cpuinfo 2>/dev/null; then
        vps_type="KVM/QEMU"
    elif [[ -f /sys/hypervisor/uuid ]] && [[ $(head -c 3 /sys/hypervisor/uuid) == "ec2" ]]; then
        vps_type="AWS EC2"
    elif systemd-detect-virt >/dev/null 2>&1; then
        vps_type=$(systemd-detect-virt)
    fi
    
    if [[ -n "$vps_type" ]]; then
        log_info "检测到VPS环境: $vps_type"
        return 0
    else
        log_debug "未检测到明显的VPS环境特征"
        return 1
    fi
}

# 备份关键配置
backup_configs() {
    local backup_dir="/var/backups/debian-upgrade-$(date +%Y%m%d_%H%M%S)"
    log_info "备份关键配置到 $backup_dir"
    
    $USE_SUDO mkdir -p "$backup_dir"
    
    # 备份软件源配置
    $USE_SUDO cp /etc/apt/sources.list "$backup_dir/" 2>/dev/null || true
    $USE_SUDO cp -r /etc/apt/sources.list.d/ "$backup_dir/" 2>/dev/null || true
    $USE_SUDO cp -r /etc/apt/preferences.d/ "$backup_dir/" 2>/dev/null || true
    
    # 备份关键系统文件
    $USE_SUDO cp /etc/fstab "$backup_dir/" 2>/dev/null || true
    $USE_SUDO cp /etc/hostname "$backup_dir/" 2>/dev/null || true
    $USE_SUDO cp /etc/hosts "$backup_dir/" 2>/dev/null || true
    $USE_SUDO cp -r /etc/network/ "$backup_dir/" 2>/dev/null || true
    $USE_SUDO cp -r /etc/ssh/ "$backup_dir/" 2>/dev/null || true
    
    # 备份包列表
    dpkg --get-selections > "$backup_dir/package-selections.txt" 2>/dev/null || true
    
    echo "$backup_dir" > /tmp/debian_upgrade_backup_path
    
    log_success "配置已备份到 $backup_dir"
}

# 修复常见的VPS问题
fix_vps_issues() {
    log_info "修复常见的VPS问题..."
    
    # 修复GPG密钥问题
    if [[ -f /etc/apt/trusted.gpg.d/debian-archive-keyring.gpg ]]; then
        log_debug "Debian密钥环已存在"
    else
        log_info "安装Debian密钥环..."
        $USE_SUDO apt-get update -qq
        $USE_SUDO apt-get install -y debian-archive-keyring
    fi
    
    # 修复时区问题
    if [[ ! -f /etc/timezone ]]; then
        log_info "设置默认时区..."
        echo "UTC" | $USE_SUDO tee /etc/timezone > /dev/null
        $USE_SUDO dpkg-reconfigure -f noninteractive tzdata
    fi
    
    # 修复locale问题
    if ! locale -a | grep -q "en_US.utf8\|C.UTF-8" 2>/dev/null; then
        log_info "配置locale..."
        $USE_SUDO apt-get install -y locales
        echo "en_US.UTF-8 UTF-8" | $USE_SUDO tee -a /etc/locale.gen > /dev/null
        $USE_SUDO locale-gen
    fi
    
    # 修复DNS问题
    if [[ ! -s /etc/resolv.conf ]]; then
        log_info "修复DNS配置..."
        echo -e "nameserver 8.8.8.8\nnameserver 8.8.4.4" | $USE_SUDO tee /etc/resolv.conf > /dev/null
    fi
    
    log_success "VPS问题修复完成"
}

# 清理冲突的软件源
clean_conflicting_sources() {
    log_info "清理冲突的软件源配置..."
    
    # 禁用第三方源
    if [[ -d /etc/apt/sources.list.d/ ]]; then
        $USE_SUDO find /etc/apt/sources.list.d/ -name "*.list" -exec mv {} {}.disabled \; 2>/dev/null || true
    fi
    
    # 清理apt preferences
    if [[ -d /etc/apt/preferences.d/ ]]; then
        $USE_SUDO find /etc/apt/preferences.d/ -name "*" -exec mv {} {}.disabled \; 2>/dev/null || true
    fi
    
    log_success "冲突源配置已清理"
}

# 智能选择软件源镜像
select_mirror() {
    local country_code=""
    local mirror_url="http://deb.debian.org/debian"
    
    # 尝试检测地理位置选择合适的镜像
    if command -v curl >/dev/null 2>&1; then
        country_code=$(curl -s --connect-timeout 5 ipinfo.io/country 2>/dev/null || echo "")
    fi
    
    case "$country_code" in
        "CN")
            # 中国镜像
            for mirror in "https://mirrors.tuna.tsinghua.edu.cn/debian" "https://mirrors.ustc.edu.cn/debian" "http://mirrors.163.com/debian"; do
                if curl -s --connect-timeout 5 "$mirror/dists/" >/dev/null 2>&1; then
                    mirror_url="$mirror"
                    log_info "使用中国镜像: $mirror_url"
                    break
                fi
            done
            ;;
        "US")
            mirror_url="http://ftp.us.debian.org/debian"
            ;;
        "GB"|"IE")
            mirror_url="http://ftp.uk.debian.org/debian"
            ;;
        "DE"|"AT"|"CH")
            mirror_url="http://ftp.de.debian.org/debian"
            ;;
        "JP")
            mirror_url="http://ftp.jp.debian.org/debian"
            ;;
    esac
    
    echo "$mirror_url"
}

# 更新软件源配置
update_sources_list() {
    local target_version=$1
    local target_codename=$2
    local mirror_url=$(select_mirror)
    local security_url="http://deb.debian.org/debian-security"
    
    log_info "更新软件源到 Debian $target_version ($target_codename)"
    
    # 为中国用户使用中科大安全更新源
    if [[ "$mirror_url" =~ "tuna.tsinghua.edu.cn" ]]; then
        security_url="https://mirrors.tuna.tsinghua.edu.cn/debian-security"
    elif [[ "$mirror_url" =~ "ustc.edu.cn" ]]; then
        security_url="https://mirrors.ustc.edu.cn/debian-security"
    fi
    
    # 生成sources.list内容
    local sources_content=""
    
    if [[ "$target_version" -ge "12" ]]; then
        # Debian 12+ 包含non-free-firmware
        sources_content="# Debian $target_version ($target_codename) 官方软件源
deb $mirror_url $target_codename main contrib non-free non-free-firmware
deb-src $mirror_url $target_codename main contrib non-free non-free-firmware

# 安全更新
deb $security_url $target_codename-security main contrib non-free non-free-firmware
deb-src $security_url $target_codename-security main contrib non-free non-free-firmware

# 常规更新
deb $mirror_url $target_codename-updates main contrib non-free non-free-firmware
deb-src $mirror_url $target_codename-updates main contrib non-free non-free-firmware"
    else
        # Debian 11及以下版本
        sources_content="# Debian $target_version ($target_codename) 官方软件源
deb $mirror_url $target_codename main contrib non-free
deb-src $mirror_url $target_codename main contrib non-free

# 安全更新
deb $security_url $target_codename/updates main contrib non-free
deb-src $security_url $target_codename/updates main contrib non-free

# 常规更新  
deb $mirror_url $target_codename-updates main contrib non-free
deb-src $mirror_url $target_codename-updates main contrib non-free"
    fi
    
    # 写入新的sources.list
    echo "$sources_content" | $USE_SUDO tee /etc/apt/sources.list > /dev/null
    
    log_success "软件源配置已更新"
}

# 强化的APT清理
enhanced_apt_cleanup() {
    log_info "执行强化APT清理..."
    
    # 清理APT缓存和锁定文件
    $USE_SUDO rm -rf /var/lib/apt/lists/* 2>/dev/null || true
    $USE_SUDO rm -f /var/cache/apt/archives/lock 2>/dev/null || true
    $USE_SUDO rm -f /var/lib/dpkg/lock* 2>/dev/null || true
    $USE_SUDO rm -f /var/lib/apt/lists/lock 2>/dev/null || true
    
    # 清理APT缓存
    $USE_SUDO apt-get clean 2>/dev/null || true
    $USE_SUDO apt-get autoclean 2>/dev/null || true
    
    # 重新配置dpkg
    $USE_SUDO dpkg --configure -a 2>/dev/null || true
    
    log_success "强化APT清理完成"
}

# 智能更新包列表
smart_update_packages() {
    log_info "更新软件包列表..."
    
    local max_attempts=5
    local attempt=1
    local delay=5
    
    while [[ $attempt -le $max_attempts ]]; do
        log_info "尝试更新包列表 (第 $attempt/$max_attempts 次)"
        
        # 尝试更新
        if timeout 300 $USE_SUDO apt-get update 2>/dev/null; then
            log_success "软件包列表更新成功"
            return 0
        else
            log_warning "第 $attempt 次更新失败"
            
            if [[ $attempt -lt $max_attempts ]]; then
                log_info "等待 $delay 秒后重试..."
                sleep $delay
                delay=$((delay * 2))  # 指数退避
                
                # 在重试前清理
                enhanced_apt_cleanup
            fi
            
            attempt=$((attempt + 1))
        fi
    done
    
    log_error "软件包列表更新失败，已尝试 $max_attempts 次"
    return 1
}

# 高级系统修复
advanced_system_repair() {
    log_info "执行高级系统修复..."
    
    # 修复损坏的包
    log_info "修复损坏的软件包..."
    $USE_SUDO apt-get --fix-broken install -y 2>/dev/null || true
    $USE_SUDO dpkg --configure -a 2>/dev/null || true
    
    # 修复依赖关系
    log_info "修复依赖关系..."
    $USE_SUDO apt-get -f install -y 2>/dev/null || true
    
    # 重新安装关键包
    local essential_packages="base-files base-passwd bash coreutils"
    for package in $essential_packages; do
        if dpkg -l "$package" 2>/dev/null | grep -q "^ii"; then
            log_debug "重新安装关键包: $package"
            $USE_SUDO apt-get install --reinstall -y "$package" 2>/dev/null || true
        fi
    done
    
    log_success "高级系统修复完成"
}

# 渐进式升级
progressive_upgrade() {
    local upgrade_phase=$1  # minimal, safe, full
    
    log_info "执行${upgrade_phase}升级阶段..."
    
    case "$upgrade_phase" in
        "minimal")
            # 最小升级 - 只升级已安装的包
            $USE_SUDO apt-get upgrade -y --with-new-pkgs
            ;;
        "safe")
            # 安全升级 - 不删除包的情况下升级
            $USE_SUDO apt-get upgrade -y
            ;;
        "full")
            # 完整升级 - 可能删除/安装新包
            $USE_SUDO apt-get dist-upgrade -y
            ;;
    esac
    
    log_success "${upgrade_phase}升级阶段完成"
}

# 执行分阶段升级
perform_staged_upgrade() {
    log_info "开始执行分阶段系统升级..."
    
    # 阶段0: 系统修复
    advanced_system_repair
    
    # 阶段1: 最小升级
    progressive_upgrade "minimal"
    
    # 阶段2: 安全升级  
    progressive_upgrade "safe"
    
    # 阶段3: 完整升级
    progressive_upgrade "full"
    
    # 清理
    log_info "清理不需要的软件包和缓存..."
    $USE_SUDO apt-get autoremove -y --purge 2>/dev/null || true
    $USE_SUDO apt-get autoclean 2>/dev/null || true
    
    log_success "分阶段系统升级完成"
}

# 验证升级结果
verify_upgrade() {
    local expected_version=$1
    local current_version=$(get_current_version)
    
    log_info "验证升级结果..."
    
    if [[ "$current_version" == "$expected_version" ]]; then
        log_success "升级验证成功！当前版本: Debian $current_version"
        
        # 额外验证
        log_info "执行额外验证检查..."
        
        # 检查关键服务
        local services="ssh networking"
        for service in $services; do
            if systemctl is-active "$service" >/dev/null 2>&1; then
                log_debug "服务 $service 运行正常"
            else
                log_warning "服务 $service 可能存在问题"
            fi
        done
        
        # 检查网络连接
        if ping -c 1 debian.org >/dev/null 2>&1; then
            log_debug "网络连接正常"
        else
            log_warning "网络连接可能存在问题"
        fi
        
        return 0
    else
        log_error "升级验证失败！期望版本: $expected_version, 当前版本: $current_version"
        return 1
    fi
}

# 主升级逻辑
main_upgrade() {
    local current_version=$(get_current_version)
    local version_info=$(get_version_info "$current_version")
    local current_codename=$(echo "$version_info" | cut -d'|' -f1)
    local current_status=$(echo "$version_info" | cut -d'|' -f2)
    local next_version=$(get_next_version "$current_version")
    
    log_info "========================================="
    log_info "Debian自动升级脚本 v$SCRIPT_VERSION"
    log_info "========================================="
    log_info "当前系统版本: Debian $current_version ($current_codename) [$current_status]"
    
    # 检测VPS环境
    detect_vps_environment
    
    if [[ -z "$next_version" ]]; then
        if [[ "$current_status" == "stable" ]]; then
            log_success "恭喜！您已经在使用最新稳定版本的Debian $current_version"
            if [[ "${STABLE_ONLY:-}" != "1" ]]; then
                echo
                log_info "💡 提示："
                log_info "- 当前版本是最新的稳定版本，建议保持使用"
                log_info "- 如需体验新功能，可使用 --allow-testing 选项升级到测试版本"
                log_info "- 测试版本可能不稳定，不建议在生产环境使用"
            fi
        else
            log_info "您正在使用 Debian $current_version ($current_status)"
            if [[ "$current_status" == "testing" || "$current_status" == "unstable" ]]; then
                log_info "当前版本为非稳定版本，如需回到稳定版本请手动操作"
            fi
        fi
        exit 0
    fi
    
    local next_version_info=$(get_version_info "$next_version")
    local next_codename=$(echo "$next_version_info" | cut -d'|' -f1)
    local next_status=$(echo "$next_version_info" | cut -d'|' -f2)
    
    if [[ "$next_codename" == "unknown" ]]; then
        log_warning "下一个版本 Debian $next_version 可能还未发布或不被支持"
        log_info "当前版本 Debian $current_version 可能已经是最新的稳定版本"
        exit 0
    fi
    
    log_info "准备升级到: Debian $next_version ($next_codename) [$next_status]"
    
    # 改进的风险提示和用户确认
    if [[ "$next_status" == "testing" || "$next_status" == "unstable" ]]; then
        echo
        echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
        log_warning "⚠️  重要警告：即将升级到非稳定版本！"
        echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
        echo
        echo "📋 版本信息："
        echo "   • 目标版本: Debian $next_version ($next_codename)"
        echo "   • 版本状态: $next_status"
        echo "   • 稳定性: 非稳定版本"
        echo
        echo "⚠️  风险说明："
        echo "   • 可能包含未修复的bug和不稳定的功能"
        echo "   • 软件包可能不完整或存在兼容性问题"
        echo "   • 不建议在生产环境中使用"
        echo "   • 升级过程可能失败或导致系统不稳定"
        echo
        echo "💡 建议："
        echo "   • 生产服务器: 保持当前稳定版本"
        echo "   • 测试环境: 可以谨慎尝试"
        echo "   • 确保有完整的备份和恢复方案"
        echo "   • 确保有VPS控制台访问权限"
        echo
        
        if [[ "${FORCE:-}" == "1" ]]; then
            log_warning "强制模式已启用，跳过确认直接升级"
        else
            # 需要明确确认
            if get_user_confirmation "您确定要升级到测试版本吗？请输入 'YES' 确认，或 'no' 取消: "; then
                log_info "用户确认升级到测试版本"
            else
                log_info "用户取消升级"
                log_success "保持当前稳定版本 Debian $current_version - 明智的选择！"
                exit 0
            fi
        fi
        
        echo
        log_warning "最后确认：即将开始升级到测试版本..."
        if [[ "${FORCE:-}" != "1" ]]; then
            sleep 3
        fi
    else
        # 稳定版本的常规确认
        echo
        log_info "🎯 升级到稳定版本："
        log_info "   从: Debian $current_version ($current_codename) [$current_status]"
        log_info "   到: Debian $next_version ($next_codename) [$next_status]"
        echo
        
        if [[ "${FORCE:-}" == "1" ]]; then
            log_info "强制模式已启用，自动确认升级"
        else
            read -p "是否继续升级到 Debian $next_version ($next_codename)? [y/N]: " -n 1 -r </dev/tty
            echo
            if [[ ! $REPLY =~ ^[Yy]$ ]]; then
                log_info "用户取消升级"
                exit 0
            fi
        fi
    fi
    
    # 执行升级步骤
    log_info "开始升级过程..."
    
    backup_configs
    fix_vps_issues
    clean_conflicting_sources
    update_sources_list "$next_version" "$next_codename"
    enhanced_apt_cleanup
    
    if ! smart_update_packages; then
        log_error "更新软件包列表失败，升级中止"
        exit 1
    fi
    
    perform_staged_upgrade
    
    if verify_upgrade "$next_version"; then
        echo
        log_success "========================================="
        log_success "升级完成！Debian $current_version -> $next_version"
        log_success "========================================="
        echo
        
        # 显示升级后信息
        log_info "升级摘要:"
        log_info "- 原版本: Debian $current_version ($current_codename)"
        log_info "- 新版本: Debian $next_version ($next_codename)"
        log_info "- 配置备份: $(cat /tmp/debian_upgrade_backup_path 2>/dev/null || echo '未知')"
        
        echo
        log_info "重要提醒："
        log_info "1. 建议重启系统以确保所有更改生效"
        log_info "2. 重启后可以再次运行此脚本继续升级到更新版本"
        log_info "3. 如遇问题，可使用备份配置进行恢复"
        
        echo
        if [[ "${FORCE:-}" == "1" ]]; then
            log_info "强制模式已启用，建议手动重启系统"
        else
            read -p "是否现在重启系统? [y/N]: " -n 1 -r </dev/tty
            echo
            if [[ $REPLY =~ ^[Yy]$ ]]; then
                log_info "正在重启系统..."
                $USE_SUDO reboot
            else
                log_info "请稍后手动重启系统"
            fi
        fi
    else
        log_error "升级验证失败，请检查系统状态"
        if [[ -f /tmp/debian_upgrade_backup_path ]]; then
            log_info "如需恢复，备份位置: $(cat /tmp/debian_upgrade_backup_path)"
        fi
        exit 1
    fi
}

# 显示帮助信息
show_help() {
    cat << EOF
Debian自动逐级升级脚本 v$SCRIPT_VERSION

用法: $0 [选项]

选项:
  -h, --help          显示此帮助信息
  -v, --version       显示当前Debian版本信息
  -c, --check         检查是否有可用升级
  -d, --debug         启用调试模式
  --fix-only          仅执行系统修复，不进行升级
  --force             强制执行升级（跳过确认）
  --stable-only       仅升级到稳定版本，跳过测试版本
  --allow-testing     允许升级到测试版本（默认行为）

功能特性:
  ✓ 自动检测当前Debian版本和目标版本
  ✓ 逐级安全升级，避免跨版本问题
  ✓ 智能软件源选择和镜像优化
  ✓ VPS环境适配和问题修复
  ✓ 分阶段升级减少风险
  ✓ 完整的配置备份和恢复
  ✓ 网络和系统环境检查
  ✓ 详细的日志和错误处理
  ✓ 智能版本控制和风险提示

支持的Debian版本:
  - Debian 8 (Jessie) → 9 (Stretch)
  - Debian 9 (Stretch) → 10 (Buster)  
  - Debian 10 (Buster) → 11 (Bullseye)
  - Debian 11 (Bullseye) → 12 (Bookworm)
  - Debian 12 (Bookworm) → 13 (Trixie) [测试版本]

示例:
  $0                    # 执行自动升级
  $0 --check            # 检查可用升级
  $0 --version          # 显示版本信息
  $0 --fix-only         # 仅修复系统问题
  $0 --debug            # 启用调试模式
  $0 --stable-only      # 仅升级到稳定版本
  $0 --force            # 强制升级（跳过确认）
  
注意事项:
  - 升级前会自动备份重要配置
  - 建议在升级前创建系统快照
  - VPS用户请确保有控制台访问权限
  - 测试版本升级需要明确确认
  - 升级过程可能需要较长时间

安全提示:
  - Debian 12 是当前稳定版本，建议保持使用
  - Debian 13 为测试版本，不建议生产环境使用
  - 使用 --stable-only 可避免意外升级到测试版本
EOF
}

# 检查可用升级
check_upgrade() {
    local current_version=$(get_current_version)
    local version_info=$(get_version_info "$current_version")
    local current_codename=$(echo "$version_info" | cut -d'|' -f1)
    local current_status=$(echo "$version_info" | cut -d'|' -f2)
    local next_version=$(get_next_version "$current_version")
    
    echo "========================================="
    echo "Debian升级检查"
    echo "========================================="
    echo "当前版本: Debian $current_version ($current_codename) [$current_status]"
    
    if [[ -z "$next_version" ]]; then
        if [[ "$current_status" == "stable" ]]; then
            echo "状态: ✓ 已是最新稳定版本"
            if [[ "${STABLE_ONLY:-}" != "1" ]]; then
                echo
                echo "💡 说明："
                echo "- 当前使用最新稳定版本，建议保持"
                echo "- 如需体验新功能，可添加 --allow-testing 选项"
                echo "- 测试版本风险较高，仅建议测试环境使用"
            fi
        else
            echo "状态: ✓ 已是最新版本 ($current_status)"
        fi
    else
        local next_version_info=$(get_version_info "$next_version")
        local next_codename=$(echo "$next_version_info" | cut -d'|' -f1)
        local next_status=$(echo "$next_version_info" | cut -d'|' -f2)
        
        if [[ "$next_codename" == "unknown" ]]; then
            echo "状态: ✓ 已是最新稳定版本"
        else
            echo "可升级到: Debian $next_version ($next_codename) [$next_status]"
            
            if [[ "$next_status" == "testing" || "$next_status" == "unstable" ]]; then
                echo "警告: ⚠️  目标版本为非稳定版本"
                echo "建议: 💡 生产环境请保持当前稳定版本"
                echo "选项: 🛡️  使用 --stable-only 可避免升级到测试版本"
            else
                echo "推荐: ✅ 可安全升级到稳定版本"
            fi
        fi
    fi
    
    echo "========================================="
    
    # 显示系统状态
    echo "系统状态检查:"
    
    # 磁盘空间
    local disk_usage=$(df -h / | awk 'NR==2 {print $5}')
    local available_space=$(df / | awk 'NR==2 {print $4}')
    echo "- 磁盘使用: $disk_usage"
    if [[ $available_space -lt 2097152 ]]; then
        echo "  ⚠️  可用空间不足2GB"
    else
        echo "  ✓ 磁盘空间充足"
    fi
    
    # 内存状态
    local memory_info=$(free -h | awk 'NR==2{printf "使用: %s/%s", $3,$2}')
    echo "- 内存状态: $memory_info"
    
    # 网络连接
    if ping -c 1 deb.debian.org >/dev/null 2>&1; then
        echo "- 网络连接: ✓ 正常"
    else
        echo "- 网络连接: ⚠️  无法连接到Debian官方源"
    fi
    
    # VPS环境检测
    if detect_vps_environment >/dev/null 2>&1; then
        echo "- 环境类型: VPS/虚拟机"
    else
        echo "- 环境类型: 物理机或未知"
    fi
    
    echo "========================================="
}

# 系统修复模式
fix_only_mode() {
    log_info "========================================="
    log_info "仅执行系统修复模式"
    log_info "========================================="
    
    check_system
    fix_vps_issues
    enhanced_apt_cleanup
    smart_update_packages
    advanced_system_repair
    
    log_success "系统修复完成"
    log_info "系统已优化，可以尝试运行正常升级"
}

# 主函数
main() {
    # 解析命令行参数
    while [[ $# -gt 0 ]]; do
        case $1 in
            -h|--help)
                show_help
                exit 0
                ;;
            -v|--version)
                local current_version=$(get_current_version)
                local version_info=$(get_version_info "$current_version")
                local current_codename=$(echo "$version_info" | cut -d'|' -f1)
                local current_status=$(echo "$version_info" | cut -d'|' -f2)
                echo "Debian $current_version ($current_codename) [$current_status]"
                exit 0
                ;;
            -c|--check)
                check_upgrade
                exit 0
                ;;
            -d|--debug)
                export DEBUG=1
                log_debug "调试模式已启用"
                shift
                ;;
            --fix-only)
                check_root
                check_system
                fix_only_mode
                exit 0
                ;;
            --force)
                export FORCE=1
                log_warning "强制模式已启用，将跳过确认提示"
                shift
                ;;
            --stable-only)
                export STABLE_ONLY=1
                log_info "仅升级稳定版本模式已启用"
                shift
                ;;
            --allow-testing)
                export STABLE_ONLY=0
                log_info "允许升级测试版本模式已启用"
                shift
                ;;
            *)
                log_error "未知选项: $1"
                echo "使用 '$0 --help' 查看帮助信息"
                exit 1
                ;;
        esac
    done
    
    # 默认执行升级
    check_root
    check_system
    main_upgrade
}

# 错误处理
trap 'log_error "脚本执行过程中发生错误，退出码: $?"' ERR

# 清理函数
cleanup() {
    log_debug "执行清理操作..."
    rm -f /tmp/debian_upgrade_backup_path 2>/dev/null || true
}

# 注册退出时的清理函数
trap cleanup EXIT

# 脚本入口
main "$@"
