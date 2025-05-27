#!/bin/bash

# Debian自动逐级升级脚本 - 修复版
# 功能：自动检测当前版本并升级到下一个版本，直到最新版本
# 适用于大部分Debian系统，包括VPS环境

set -e  # 遇到错误立即退出

# 脚本版本
SCRIPT_VERSION="2.2"

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

# 改进版本检测 - 支持更多边缘情况
get_current_version() {
    local version_id=""
    local debian_version=""
    
    # 方法1: 从os-release获取版本
    if [[ -f /etc/os-release ]]; then
        version_id=$(grep "^VERSION_ID=" /etc/os-release | cut -d'"' -f2 2>/dev/null || echo "")
        log_debug "从os-release获取版本: $version_id"
    fi
    
    # 方法2: 从debian_version推断
    if [[ -f /etc/debian_version ]]; then
        debian_version=$(cat /etc/debian_version 2>/dev/null || echo "")
        log_debug "debian_version内容: $debian_version"
        
        case "$debian_version" in
            "8."*|"jessie"*) local detected_version="8" ;;
            "9."*|"stretch"*) local detected_version="9" ;;
            "10."*|"buster"*) local detected_version="10" ;;
            "11."*|"bullseye"*) local detected_version="11" ;;
            "12."*|"bookworm"*) local detected_version="12" ;;
            "13."*|"trixie"*) local detected_version="13" ;;
            "14."*|"forky"*) local detected_version="14" ;;
            *) local detected_version="" ;;
        esac
        
        # 如果os-release没有VERSION_ID，使用推断的版本
        if [[ -z "$version_id" && -n "$detected_version" ]]; then
            version_id="$detected_version"
            log_debug "从debian_version推断版本: $version_id"
        fi
    fi
    
    # 方法3: 从APT策略检测
    if [[ -z "$version_id" ]]; then
        local apt_policy=$(apt-cache policy 2>/dev/null | head -20)
        if echo "$apt_policy" | grep -q "bookworm"; then
            version_id="12"
        elif echo "$apt_policy" | grep -q "bullseye"; then
            version_id="11"
        elif echo "$apt_policy" | grep -q "buster"; then
            version_id="10"
        elif echo "$apt_policy" | grep -q "stretch"; then
            version_id="9"
        elif echo "$apt_policy" | grep -q "jessie"; then
            version_id="8"
        elif echo "$apt_policy" | grep -q "trixie"; then
            version_id="13"
        fi
        log_debug "从APT策略检测版本: $version_id"
    fi
    
    # 方法4: 基于内核版本推断（最后手段）
    if [[ -z "$version_id" ]]; then
        local kernel_version=$(uname -r)
        log_debug "内核版本: $kernel_version"
        
        # 这只是一个粗略的估计
        if [[ "$kernel_version" =~ ^6\. ]]; then
            version_id="12"  # Debian 12 通常使用6.x内核
        elif [[ "$kernel_version" =~ ^5\. ]]; then
            version_id="11"  # Debian 11 通常使用5.x内核
        elif [[ "$kernel_version" =~ ^4\.19 ]]; then
            version_id="10"  # Debian 10 使用4.19内核
        elif [[ "$kernel_version" =~ ^4\. ]]; then
            version_id="9"   # Debian 9 使用4.x内核
        fi
        log_debug "从内核版本推断: $version_id"
    fi
    
    if [[ -z "$version_id" ]]; then
        log_error "无法确定Debian版本，请检查系统状态"
        log_error "调试信息："
        log_error "- /etc/debian_version: $debian_version"
        log_error "- 内核版本: $(uname -r)"
        log_error "- 系统信息: $(cat /etc/os-release 2>/dev/null | head -5 || echo '无法读取')"
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
        "15") echo "sid|unstable" ;;
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
        "14") echo "15" ;;
        *) echo "" ;;
    esac
}

# 检测VPS环境
detect_vps_environment() {
    local vps_type=""
    local vps_provider=""
    
    # 检测常见VPS环境
    if [[ -f /proc/vz/version ]]; then
        vps_type="OpenVZ"
    elif [[ -d /proc/xen ]]; then
        vps_type="Xen"
    elif grep -q "VMware" /proc/scsi/scsi 2>/dev/null; then
        vps_type="VMware"
    elif grep -q "QEMU" /proc/cpuinfo 2>/dev/null; then
        vps_type="KVM/QEMU"
    elif [[ -f /sys/hypervisor/uuid ]] && [[ $(head -c 3 /sys/hypervisor/uuid 2>/dev/null) == "ec2" ]]; then
        vps_type="AWS EC2"
    elif systemd-detect-virt >/dev/null 2>&1; then
        vps_type=$(systemd-detect-virt)
    fi
    
    # 检测云服务提供商
    if [[ -f /sys/class/dmi/id/sys_vendor ]]; then
        local vendor=$(cat /sys/class/dmi/id/sys_vendor 2>/dev/null)
        case "$vendor" in
            *"Amazon"*) vps_provider="AWS" ;;
            *"Google"*) vps_provider="Google Cloud" ;;
            *"Microsoft"*) vps_provider="Azure" ;;
            *"DigitalOcean"*) vps_provider="DigitalOcean" ;;
            *"Linode"*) vps_provider="Linode" ;;
            *"Vultr"*) vps_provider="Vultr" ;;
        esac
    fi
    
    # 检查是否在容器中
    if [[ -f /.dockerenv ]]; then
        vps_type="Docker容器"
    elif grep -q "container=lxc" /proc/1/environ 2>/dev/null; then
        vps_type="LXC容器"
    fi
    
    if [[ -n "$vps_type" ]]; then
        if [[ -n "$vps_provider" ]]; then
            log_info "检测到VPS环境: $vps_type ($vps_provider)"
        else
            log_info "检测到VPS环境: $vps_type"
        fi
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
    
    # 备份当前版本信息
    get_current_version > "$backup_dir/original-version.txt" 2>/dev/null || true
    cat /etc/debian_version > "$backup_dir/original-debian-version.txt" 2>/dev/null || true
    
    echo "$backup_dir" > /tmp/debian_upgrade_backup_path
    
    log_success "配置已备份到 $backup_dir"
}

# 修复常见的VPS问题
fix_vps_issues() {
    log_info "修复常见的VPS问题..."
    
    # 修复APT锁定问题
    log_debug "清理APT锁定文件..."
    $USE_SUDO rm -f /var/lib/dpkg/lock-frontend 2>/dev/null || true
    $USE_SUDO rm -f /var/lib/dpkg/lock 2>/dev/null || true
    $USE_SUDO rm -f /var/cache/apt/archives/lock 2>/dev/null || true
    $USE_SUDO rm -f /var/lib/apt/lists/lock 2>/dev/null || true
    
    # 修复损坏的dpkg状态
    log_debug "修复dpkg状态..."
    $USE_SUDO dpkg --configure -a 2>/dev/null || true
    
    # 修复GPG密钥问题
    if [[ ! -f /etc/apt/trusted.gpg.d/debian-archive-keyring.gpg ]] && [[ ! -f /usr/share/keyrings/debian-archive-keyring.gpg ]]; then
        log_info "安装Debian密钥环..."
        $USE_SUDO apt-get update -qq 2>/dev/null || true
        $USE_SUDO apt-get install -y debian-archive-keyring 2>/dev/null || {
            log_warning "无法安装密钥环，尝试手动导入密钥"
            # 手动导入密钥的备用方案
            for key in 648ACFD622F3D138 0E98404D386FA1D9 605C66F00D6C9793; do
                $USE_SUDO apt-key adv --keyserver keyserver.ubuntu.com --recv-keys $key 2>/dev/null || true
            done
        }
    fi
    
    # 修复时区问题
    if [[ ! -f /etc/timezone ]]; then
        log_info "设置默认时区..."
        echo "UTC" | $USE_SUDO tee /etc/timezone > /dev/null
        $USE_SUDO dpkg-reconfigure -f noninteractive tzdata 2>/dev/null || true
    fi
    
    # 修复locale问题
    if ! locale -a | grep -q "en_US.utf8\|C.UTF-8" 2>/dev/null; then
        log_info "配置locale..."
        $USE_SUDO apt-get install -y locales 2>/dev/null || true
        echo "en_US.UTF-8 UTF-8" | $USE_SUDO tee -a /etc/locale.gen > /dev/null
        $USE_SUDO locale-gen 2>/dev/null || true
    fi
    
    # 修复DNS问题
    if [[ ! -s /etc/resolv.conf ]]; then
        log_info "修复DNS配置..."
        echo -e "nameserver 8.8.8.8\nnameserver 8.8.4.4\nnameserver 1.1.1.1" | $USE_SUDO tee /etc/resolv.conf > /dev/null
    fi
    
    # 修复缺失的必要目录
    $USE_SUDO mkdir -p /var/lib/apt/lists/partial 2>/dev/null || true
    $USE_SUDO mkdir -p /var/cache/apt/archives/partial 2>/dev/null || true
    
    log_success "VPS问题修复完成"
}

# 清理冲突的软件源
clean_conflicting_sources() {
    log_info "清理冲突的软件源配置..."
    
    # 备份并禁用第三方源
    if [[ -d /etc/apt/sources.list.d/ ]]; then
        local disabled_count=0
        for file in /etc/apt/sources.list.d/*.list; do
            if [[ -f "$file" ]]; then
                $USE_SUDO mv "$file" "$file.disabled" 2>/dev/null && ((disabled_count++)) || true
            fi
        done
        if [[ $disabled_count -gt 0 ]]; then
            log_info "已禁用 $disabled_count 个第三方软件源"
        fi
    fi
    
    # 备份并禁用apt preferences
    if [[ -d /etc/apt/preferences.d/ ]]; then
        local pref_count=0
        for file in /etc/apt/preferences.d/*; do
            if [[ -f "$file" && ! "$file" =~ \.disabled$ ]]; then
                $USE_SUDO mv "$file" "$file.disabled" 2>/dev/null && ((pref_count++)) || true
            fi
        done
        if [[ $pref_count -gt 0 ]]; then
            log_info "已禁用 $pref_count 个APT偏好设置"
        fi
    fi
    
    # 清理可能有问题的配置文件
    $USE_SUDO rm -f /etc/apt/apt.conf.d/99local 2>/dev/null || true
    
    log_success "冲突源配置已清理"
}

# 智能选择软件源镜像
select_mirror() {
    local country_code=""
    local mirror_url="http://deb.debian.org/debian"
    local test_timeout=3
    
    # 尝试检测地理位置选择合适的镜像
    if command -v curl >/dev/null 2>&1; then
        country_code=$(curl -s --connect-timeout 5 --max-time 10 ipinfo.io/country 2>/dev/null || echo "")
        log_debug "检测到国家代码: $country_code"
    fi
    
    # 定义镜像列表
    local -A mirrors
    case "$country_code" in
        "CN")
            mirrors=(
                ["清华大学"]="https://mirrors.tuna.tsinghua.edu.cn/debian"
                ["中科大"]="https://mirrors.ustc.edu.cn/debian"
                ["网易"]="http://mirrors.163.com/debian"
                ["阿里云"]="https://mirrors.aliyun.com/debian"
                ["华为云"]="https://mirrors.huaweicloud.com/debian"
            )
            ;;
        "US")
            mirrors=(
                ["美国官方"]="http://ftp.us.debian.org/debian"
                ["MIT"]="http://debian.csail.mit.edu/debian"
            )
            ;;
        "JP")
            mirrors=(
                ["日本官方"]="http://ftp.jp.debian.org/debian"
                ["理研"]="http://ftp.riken.jp/Linux/debian/debian"
            )
            ;;
        "DE"|"AT"|"CH")
            mirrors=(
                ["德国官方"]="http://ftp.de.debian.org/debian"
                ["德国镜像"]="http://ftp2.de.debian.org/debian"
            )
            ;;
        "GB"|"IE")
            mirrors=(
                ["英国官方"]="http://ftp.uk.debian.org/debian"
            )
            ;;
        *)
            mirrors=(
                ["官方主站"]="http://deb.debian.org/debian"
                ["CDN"]="http://httpredir.debian.org/debian"
            )
            ;;
    esac
    
    # 测试镜像可用性
    log_debug "测试镜像可用性..."
    for name in "${!mirrors[@]}"; do
        local url="${mirrors[$name]}"
        log_debug "测试镜像: $name ($url)"
        
        if timeout $test_timeout curl -s --connect-timeout $test_timeout "$url/dists/" >/dev/null 2>&1; then
            mirror_url="$url"
            log_info "选择镜像: $name ($mirror_url)"
            break
        else
            log_debug "镜像 $name 不可用或响应慢"
        fi
    done
    
    echo "$mirror_url"
}

# 更新软件源配置
update_sources_list() {
    local target_version=$1
    local target_codename=$2
    local mirror_url=$(select_mirror)
    local security_url="http://deb.debian.org/debian-security"
    
    log_info "更新软件源到 Debian $target_version ($target_codename)"
    
    # 为中国镜像选择对应的安全更新源
    if [[ "$mirror_url" =~ "tuna.tsinghua.edu.cn" ]]; then
        security_url="https://mirrors.tuna.tsinghua.edu.cn/debian-security"
    elif [[ "$mirror_url" =~ "ustc.edu.cn" ]]; then
        security_url="https://mirrors.ustc.edu.cn/debian-security"
    elif [[ "$mirror_url" =~ "aliyun.com" ]]; then
        security_url="https://mirrors.aliyun.com/debian-security"
    fi
    
    # 生成sources.list内容
    local sources_content=""
    
    # 根据版本确定安全源格式
    if [[ "$target_version" -ge "12" ]]; then
        # Debian 12+ 包含non-free-firmware和新的安全源格式
        sources_content="# Debian $target_version ($target_codename) 官方软件源
deb $mirror_url $target_codename main contrib non-free non-free-firmware
deb-src $mirror_url $target_codename main contrib non-free non-free-firmware

# 安全更新
deb $security_url $target_codename-security main contrib non-free non-free-firmware
deb-src $security_url $target_codename-security main contrib non-free non-free-firmware

# 常规更新
deb $mirror_url $target_codename-updates main contrib non-free non-free-firmware
deb-src $mirror_url $target_codename-updates main contrib non-free non-free-firmware"
    elif [[ "$target_version" -ge "11" ]]; then
        # Debian 11 使用新的安全源格式
        sources_content="# Debian $target_version ($target_codename) 官方软件源
deb $mirror_url $target_codename main contrib non-free
deb-src $mirror_url $target_codename main contrib non-free

# 安全更新
deb $security_url $target_codename-security main contrib non-free
deb-src $security_url $target_codename-security main contrib non-free

# 常规更新
deb $mirror_url $target_codename-updates main contrib non-free
deb-src $mirror_url $target_codename-updates main contrib non-free"
    else
        # Debian 10及以下版本使用旧的安全源格式
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
    log_debug "新的sources.list内容:"
    log_debug "$(cat /etc/apt/sources.list | head -10)"
}

# 强化的APT清理
enhanced_apt_cleanup() {
    log_info "执行强化APT清理..."
    
    # 停止可能干扰的服务
    for service in unattended-upgrades apt-daily apt-daily-upgrade; do
        if systemctl is-active "$service" >/dev/null 2>&1; then
            log_debug "停止服务: $service"
            $USE_SUDO systemctl stop "$service" 2>/dev/null || true
        fi
    done
    
    # 清理APT缓存和锁定文件
    log_debug "清理APT锁定文件和缓存..."
    $USE_SUDO rm -rf /var/lib/apt/lists/* 2>/dev/null || true
    $USE_SUDO rm -f /var/cache/apt/archives/lock 2>/dev/null || true
    $USE_SUDO rm -f /var/lib/dpkg/lock* 2>/dev/null || true
    $USE_SUDO rm -f /var/lib/apt/lists/lock 2>/dev/null || true
    
    # 创建必要的目录
    $USE_SUDO mkdir -p /var/lib/apt/lists/partial 2>/dev/null || true
    $USE_SUDO mkdir -p /var/cache/apt/archives/partial 2>/dev/null || true
    
    # 清理APT缓存
    $USE_SUDO apt-get clean 2>/dev/null || true
    $USE_SUDO apt-get autoclean 2>/dev/null || true
    
    # 重新配置dpkg
    $USE_SUDO dpkg --configure -a 2>/dev/null || true
    
    # 修复可能的损坏
    $USE_SUDO apt-get --fix-broken install -y 2>/dev/null || true
    
    log_success "强化APT清理完成"
}

# 智能更新包列表
smart_update_packages() {
    log_info "更新软件包列表..."
    
    local max_attempts=5
    local attempt=1
    local base_delay=5
    
    while [[ $attempt -le $max_attempts ]]; do
        log_info "尝试更新包列表 (第 $attempt/$max_attempts 次)"
        
        # 每次重试前清理
        if [[ $attempt -gt 1 ]]; then
            enhanced_apt_cleanup
            sleep $base_delay
            base_delay=$((base_delay * 2))  # 指数退避
        fi
        
        # 尝试更新，使用更长的超时
        local update_timeout=600  # 10分钟超时
        if timeout $update_timeout $USE_SUDO apt-get update -o APT::Acquire::Retries=3 2>&1 | tee /tmp/apt_update.log; then
            # 检查是否有GPG错误
            if grep -q "NO_PUBKEY\|GPG error" /tmp/apt_update.log; then
                log_warning "检测到GPG密钥问题，尝试修复..."
                
                # 提取缺失的密钥ID
                local missing_keys=$(grep "NO_PUBKEY" /tmp/apt_update.log | sed 's/.*NO_PUBKEY \([A-F0-9]*\).*/\1/' | sort -u)
                
                # 尝试导入缺失的密钥
                for key in $missing_keys; do
                    log_info "尝试导入密钥: $key"
                    $USE_SUDO apt-key adv --keyserver keyserver.ubuntu.com --recv-keys "$key" 2>/dev/null || \
                    $USE_SUDO apt-key adv --keyserver hkp://keyserver.ubuntu.com:80 --recv-keys "$key" 2>/dev/null || \
                    $USE_SUDO apt-key adv --keyserver pgp.mit.edu --recv-keys "$
