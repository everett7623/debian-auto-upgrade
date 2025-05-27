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

# 验证sources.list文件的有效性
validate_sources_list() {
    local sources_file="/etc/apt/sources.list"
    
    log_info "验证sources.list文件有效性..."
    
    # 检查文件是否存在且可读
    if [[ ! -f "$sources_file" ]] || [[ ! -r "$sources_file" ]]; then
        log_error "sources.list文件不存在或不可读"
        return 1
    fi
    
    # 检查文件是否为空
    if [[ ! -s "$sources_file" ]]; then
        log_error "sources.list文件为空"
        return 1
    fi
    
    # 检查是否包含有效的deb行
    if ! grep -q "^deb " "$sources_file"; then
        log_error "sources.list文件不包含有效的软件源"
        return 1
    fi
    
    # 检查是否有格式错误
    local line_num=1
    while IFS= read -r line; do
        # 跳过空行和注释行
        if [[ -z "$line" ]] || [[ "$line" =~ ^[[:space:]]*# ]]; then
            ((line_num++))
            continue
        fi
        
        # 检查deb行的基本格式
        if [[ "$line" =~ ^deb(-src)?[[:space:]] ]]; then
            # 检查是否有不可见字符或编码问题
            if [[ "$line" =~ [[:cntrl:]] ]]; then
                log_error "第 $line_num 行包含控制字符或编码问题: $line"
                return 1
            fi
            
            # 检查基本格式：deb URL distribution component...
            local parts=($line)
            if [[ ${#parts[@]} -lt 3 ]]; then
                log_error "第 $line_num 行格式不正确: $line"
                return 1
            fi
        else
            log_warning "第 $line_num 行格式可能有问题: $line"
        fi
        
        ((line_num++))
    done < "$sources_file"
    
    # 测试APT是否能解析文件
    if ! $USE_SUDO apt-get update -qq --dry-run 2>/dev/null; then
        log_error "APT无法解析sources.list文件"
        return 1
    fi
    
    log_success "sources.list文件验证通过"
    return 0
}

# 更新软件源配置 - 修复编码问题
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
    
    # 创建临时文件，避免编码问题
    local temp_sources="/tmp/sources.list.tmp"
    
    # 根据版本生成sources.list内容，使用更安全的写入方式
    if [[ "$target_version" -ge "12" ]]; then
        # Debian 12+ 包含non-free-firmware和新的安全源格式
        cat > "$temp_sources" <<EOF
# Debian $target_version ($target_codename) sources
deb $mirror_url $target_codename main contrib non-free non-free-firmware
deb-src $mirror_url $target_codename main contrib non-free non-free-firmware

# Security updates
deb $security_url $target_codename-security main contrib non-free non-free-firmware
deb-src $security_url $target_codename-security main contrib non-free non-free-firmware

# Updates
deb $mirror_url $target_codename-updates main contrib non-free non-free-firmware
deb-src $mirror_url $target_codename-updates main contrib non-free non-free-firmware
EOF
    elif [[ "$target_version" -ge "11" ]]; then
        # Debian 11 使用新的安全源格式
        cat > "$temp_sources" <<EOF
# Debian $target_version ($target_codename) sources
deb $mirror_url $target_codename main contrib non-free
deb-src $mirror_url $target_codename main contrib non-free

# Security updates
deb $security_url $target_codename-security main contrib non-free
deb-src $security_url $target_codename-security main contrib non-free

# Updates
deb $mirror_url $target_codename-updates main contrib non-free
deb-src $mirror_url $target_codename-updates main contrib non-free
EOF
    else
        # Debian 10及以下版本使用旧的安全源格式
        cat > "$temp_sources" <<EOF
# Debian $target_version ($target_codename) sources
deb $mirror_url $target_codename main contrib non-free
deb-src $mirror_url $target_codename main contrib non-free

# Security updates
deb $security_url $target_codename/updates main contrib non-free
deb-src $security_url $target_codename/updates main contrib non-free

# Updates
deb $mirror_url $target_codename-updates main contrib non-free
deb-src $mirror_url $target_codename-updates main contrib non-free
EOF
    fi
    
    # 验证临时文件是否正确创建
    if [[ ! -f "$temp_sources" ]] || [[ ! -s "$temp_sources" ]]; then
        log_error "无法创建临时源文件"
        return 1
    fi
    
    # 验证文件内容是否有效
    if ! grep -q "^deb " "$temp_sources"; then
        log_error "生成的源文件格式无效"
        return 1
    fi
    
    # 安全地移动文件
    $USE_SUDO mv "$temp_sources" /etc/apt/sources.list
    
    # 设置正确的权限
    $USE_SUDO chmod 644 /etc/apt/sources.list
    $USE_SUDO chown root:root /etc/apt/sources.list
    
    # 验证最终文件
    if ! $USE_SUDO test -r /etc/apt/sources.list; then
        log_error "sources.list文件不可读"
        return 1
    fi
    
    log_success "软件源配置已更新"
    log_debug "新的sources.list内容:"
    log_debug "$(head -10 /etc/apt/sources.list)"
    
    # 清理临时文件
    rm -f "$temp_sources"
    
    return 0
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
                    $USE_SUDO apt-key adv --keyserver pgp.mit.edu --recv-keys "$key" 2>/dev/null || true
                done
                
                # 重新尝试更新
                if timeout $update_timeout $USE_SUDO apt-get update 2>/dev/null; then
                    log_success "GPG密钥修复后，软件包列表更新成功"
                    rm -f /tmp/apt_update.log
                    return 0
                fi
            else
                log_success "软件包列表更新成功"
                rm -f /tmp/apt_update.log
                return 0
            fi
        fi
        
        log_warning "第 $attempt 次更新失败"
        
        # 在重试前尝试更换镜像源
        if [[ $attempt -eq 3 ]]; then
            log_info "尝试切换到官方源重试..."
            local fallback_content="deb http://deb.debian.org/debian $(lsb_release -cs 2>/dev/null || echo 'stable') main contrib non-free"
            echo "$fallback_content" | $USE_SUDO tee /etc/apt/sources.list > /dev/null
        fi
        
        attempt=$((attempt + 1))
    done
    
    rm -f /tmp/apt_update.log
    log_error "软件包列表更新失败，已尝试 $max_attempts 次"
    return 1
}

# 高级系统修复
advanced_system_repair() {
    log_info "执行高级系统修复..."
    
    # 修复损坏的包数据库
    log_info "修复包数据库..."
    $USE_SUDO dpkg --configure -a 2>/dev/null || true
    $USE_SUDO apt-get --fix-broken install -y 2>/dev/null || true
    
    # 修复依赖关系
    log_info "修复依赖关系..."
    $USE_SUDO apt-get -f install -y 2>/dev/null || true
    
    # 检查并修复关键系统包
    local essential_packages="base-files base-passwd bash coreutils libc6"
    for package in $essential_packages; do
        if dpkg -l "$package" 2>/dev/null | grep -q "^ii"; then
            log_debug "检查关键包: $package"
            # 检查包是否有问题
            if ! dpkg -V "$package" >/dev/null 2>&1; then
                log_info "重新安装关键包: $package"
                $USE_SUDO apt-get install --reinstall -y "$package" 2>/dev/null || true
            fi
        fi
    done
    
    # 清理损坏的包缓存
    $USE_SUDO apt-get clean
    
    # 重建包缓存
    $USE_SUDO apt-get update -qq 2>/dev/null || true
    
    log_success "高级系统修复完成"
}

# 渐进式升级
progressive_upgrade() {
    local upgrade_phase=$1
    local max_attempts=3
    local attempt=1
    
    log_info "执行${upgrade_phase}升级阶段..."
    
    while [[ $attempt -le $max_attempts ]]; do
        log_debug "${upgrade_phase}升级尝试 $attempt/$max_attempts"
        
        case "$upgrade_phase" in
            "minimal")
                # 最小升级 - 只升级已安装的包，不安装新包
                if DEBIAN_FRONTEND=noninteractive $USE_SUDO apt-get upgrade -y \
                   -o Dpkg::Options::="--force-confdef" \
                   -o Dpkg::Options::="--force-confold" 2>/dev/null; then
                    break
                fi
                ;;
            "safe")
                # 安全升级 - 允许安装新包但不删除现有包
                if DEBIAN_FRONTEND=noninteractive $USE_SUDO apt-get upgrade -y --with-new-pkgs \
                   -o Dpkg::Options::="--force-confdef" \
                   -o Dpkg::Options::="--force-confold" 2>/dev/null; then
                    break
                fi
                ;;
            "full")
                # 完整升级 - 可能删除/安装新包
                if DEBIAN_FRONTEND=noninteractive $USE_SUDO apt-get dist-upgrade -y \
                   -o Dpkg::Options::="--force-confdef" \
                   -o Dpkg::Options::="--force-confold" 2>/dev/null; then
                    break
                fi
                ;;
        esac
        
        if [[ $attempt -lt $max_attempts ]]; then
            log_warning "${upgrade_phase}升级第 $attempt 次失败，重试中..."
            advanced_system_repair
            sleep 5
        fi
        
        attempt=$((attempt + 1))
    done
    
    if [[ $attempt -gt $max_attempts ]]; then
        log_error "${upgrade_phase}升级失败，已尝试 $max_attempts 次"
        return 1
    fi
    
    log_success "${upgrade_phase}升级阶段完成"
    return 0
}

# 执行分阶段升级
perform_staged_upgrade() {
    log_info "开始执行分阶段系统升级..."
    
    # 阶段0: 系统预修复
    log_info "阶段0: 系统预修复"
    advanced_system_repair
    
    # 阶段1: 最小升级
    log_info "阶段1: 最小升级"
    if ! progressive_upgrade "minimal"; then
        log_error "最小升级失败，升级中止"
        return 1
    fi
    
    # 阶段2: 安全升级  
    log_info "阶段2: 安全升级"
    if ! progressive_upgrade "safe"; then
        log_warning "安全升级失败，继续尝试完整升级"
    fi
    
    # 阶段3: 完整升级
    log_info "阶段3: 完整升级"
    if ! progressive_upgrade "full"; then
        log_error "完整升级失败"
        return 1
    fi
    
    # 阶段4: 后续清理
    log_info "阶段4: 系统清理"
    log_info "清理不需要的软件包..."
    $USE_SUDO apt-get autoremove -y --purge 2>/dev/null || true
    $USE_SUDO apt-get autoclean 2>/dev/null || true
    
    # 重新配置可能需要配置的包
    log_info "重新配置系统包..."
    $USE_SUDO dpkg --configure -a 2>/dev/null || true
    
    log_success "分阶段系统升级完成"
    return 0
}

# 验证升级结果
verify_upgrade() {
    local expected_version=$1
    local current_version=$(get_current_version)
    
    log_info "验证升级结果..."
    log_debug "期望版本: $expected_version, 检测到版本: $current_version"
    
    if [[ "$current_version" == "$expected_version" ]]; then
        log_success "✅ 升级验证成功！当前版本: Debian $current_version"
        
        # 执行额外验证检查
        log_info "执行系统健康检查..."
        
        # 检查关键服务状态
        local critical_services="ssh networking systemd-resolved"
        local service_issues=0
        
        for service in $critical_services; do
            if systemctl is-active "$service" >/dev/null 2>&1; then
                log_debug "✅ 服务 $service 运行正常"
            elif systemctl list-unit-files "$service.service" >/dev/null 2>&1; then
                log_warning "⚠️  服务 $service 可能存在问题"
                ((service_issues++))
            fi
        done
        
        # 检查网络连接
        local network_ok=0
        for host in debian.org google.com 8.8.8.8; do
            if ping -c 1 -W 3 "$host" >/dev/null 2>&1; then
                log_debug "✅ 网络连接正常 ($host)"
                network_ok=1
                break
            fi
        done
        
        if [[ $network_ok -eq 0 ]]; then
            log_warning "⚠️  网络连接可能存在问题"
            ((service_issues++))
        fi
        
        # 检查包管理器状态
        if apt-get check >/dev/null 2>&1; then
            log_debug "✅ 包管理器状态正常"
        else
            log_warning "⚠️  包管理器可能存在问题"
            ((service_issues++))
        fi
        
        # 检查文件系统
        if [[ $(df / | awk 'NR==2 {print $5}' | tr -d '%') -gt 95 ]]; then
            log_warning "⚠️  根分区空间不足"
            ((service_issues++))
        fi
        
        # 总结验证结果
        if [[ $service_issues -eq 0 ]]; then
            log_success "🎉 系统升级完全成功，所有检查均通过！"
        else
            log_warning "⚠️  升级成功但发现 $service_issues 个潜在问题，建议检查"
        fi
        
        return 0
    else
        log_error "❌ 升级验证失败！"
        log_error "   期望版本: Debian $expected_version"
        log_error "   当前版本: Debian $current_version"
        
        # 提供诊断信息
        log_info "诊断信息："
        log_info "- /etc/debian_version: $(cat /etc/debian_version 2>/dev/null || echo '无法读取')"
        log_info "- /etc/os-release VERSION_ID: $(grep VERSION_ID /etc/os-release 2>/dev/null || echo '无法读取')"
        
        return 1
    fi
}

# 升级后清理和优化
post_upgrade_optimization() {
    log_info "执行升级后优化..."
    
    # 更新系统数据库
    log_debug "更新系统数据库..."
    $USE_SUDO updatedb 2>/dev/null || true
    $USE_SUDO mandb -q 2>/dev/null || true
    
    # 重建字体缓存
    if command -v fc-cache >/dev/null 2>&1; then
        log_debug "重建字体缓存..."
        fc-cache -f 2>/dev/null || true
    fi
    
    # 更新GRUB（如果存在）
    if [[ -f /boot/grub/grub.cfg ]] && command -v update-grub >/dev/null 2>&1; then
        log_debug "更新GRUB配置..."
        $USE_SUDO update-grub 2>/dev/null || true
    fi
    
    # 重启必要的服务
    local services_to_restart="networking ssh"
    for service in $services_to_restart; do
        if systemctl is-enabled "$service" >/dev/null 2>&1; then
            log_debug "重启服务: $service"
            $USE_SUDO systemctl restart "$service" 2>/dev/null || true
        fi
    done
    
    log_success "升级后优化完成"
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
    
    # 显示系统基本信息
    log_info "系统信息:"
    log_info "- 内核版本: $(uname -r)"
    log_info "- 系统架构: $(uname -m)"
    log_info "- 运行时间: $(uptime -p 2>/dev/null || echo '未知')"
    
    if [[ -z "$next_version" ]]; then
        if [[ "$current_status" == "stable" ]]; then
            log_success "🎉 恭喜！您已经在使用最新稳定版本的Debian $current_version"
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
    
    log_info "🎯 准备升级到: Debian $next_version ($next_codename) [$next_status]"
    
    # 升级风险评估和用户确认
    local risk_level="低"
    if [[ "$next_status" == "testing" ]]; then
        risk_level="中等"
    elif [[ "$next_status" == "unstable" ]]; then
        risk_level="高"
    fi
    
    log_info "升级风险等级: $risk_level"
    
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
        echo "   • 风险等级: $risk_level"
        echo "   • 稳定性: 非稳定版本"
        echo
        echo "⚠️  风险说明："
        echo "   • 可能包含未修复的bug和不稳定的功能"
        echo "   • 软件包可能不完整或存在兼容性问题"
        echo "   • 不建议在生产环境中使用"
        echo "   • 升级过程可能失败或导致系统不稳定"
        echo "   • 某些第三方软件可能无法正常工作"
        echo
        echo "💡 建议："
        echo "   • 生产服务器: 强烈建议保持当前稳定版本"
        echo "   • 测试环境: 可以谨慎尝试"
        echo "   • 确保有完整的系统备份和恢复方案"
        echo "   • 确保有VPS控制台或物理访问权限"
        echo "   • 准备回滚到稳定版本的计划"
        echo
        
        if [[ "${FORCE:-}" == "1" ]]; then
            log_warning "强制模式已启用，跳过确认直接升级"
        else
            # 需要明确确认
            if get_user_confirmation "您确定要升级到测试版本吗？请输入 'YES' 确认，或 'no' 取消: "; then
                log_info "✅ 用户确认升级到测试版本"
            else
                log_info "❌ 用户取消升级"
                log_success "保持当前稳定版本 Debian $current_version - 明智的选择！"
                exit 0
            fi
        fi
        
        echo
        log_warning "最后确认：即将开始升级到测试版本..."
        if [[ "${FORCE:-}" != "1" ]]; then
            sleep 5
        fi
    else
        # 稳定版本的常规确认
        echo
        log_info "🎯 升级到稳定版本："
        log_info "   从: Debian $current_version ($current_codename) [$current_status]"
        log_info "   到: Debian $next_version ($next_codename) [$next_status]"
        log_info "   风险等级: $risk_level"
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
    
    # 记录升级开始时间
    local upgrade_start_time=$(date)
    log_info "🚀 升级开始时间: $upgrade_start_time"
    
    # 执行升级步骤
    log_info "开始升级过程..."
    
    # 步骤1: 配置备份
    log_info "步骤1/8: 配置备份"
    if ! backup_configs; then
        log_error "配置备份失败"
        exit 1
    fi
    
    # 步骤2: VPS问题修复
    log_info "步骤2/8: VPS环境修复"
    fix_vps_issues
    
    # 步骤3: 清理冲突源
    log_info "步骤3/8: 清理冲突软件源"
    clean_conflicting_sources
    
    # 步骤4: 更新软件源
    log_info "步骤4/8: 更新软件源配置"
    if ! update_sources_list "$next_version" "$next_codename"; then
        log_error "软件源配置更新失败"
        exit 1
    fi
    
    # 验证sources.list文件
    if ! validate_sources_list; then
        log_error "sources.list文件验证失败，尝试使用备用配置"
        
        # 使用简单的备用配置
        log_info "生成备用sources.list配置..."
        $USE_SUDO tee /etc/apt/sources.list > /dev/null <<EOF
# Debian $next_version ($next_codename) - Emergency fallback
deb http://deb.debian.org/debian $next_codename main contrib non-free
deb http://deb.debian.org/debian-security $next_codename-security main contrib non-free
deb http://deb.debian.org/debian $next_codename-updates main contrib non-free
EOF
        
        # 再次验证
        if ! validate_sources_list; then
            log_error "备用配置也失败，升级中止"
            exit 1
        fi
        
        log_success "备用sources.list配置生效"
    fi
    
    # 步骤5: APT清理
    log_info "步骤5/8: APT系统清理"
    enhanced_apt_cleanup
    
    # 步骤6: 更新包列表
    log_info "步骤6/8: 更新软件包列表"
    if ! smart_update_packages; then
        log_error "更新软件包列表失败，升级中止"
        log_info "建议检查网络连接和软件源配置"
        exit 1
    fi
    
    # 步骤7: 分阶段升级
    log_info "步骤7/8: 执行系统升级"
    if ! perform_staged_upgrade; then
        log_error "系统升级失败"
        if [[ -f /tmp/debian_upgrade_backup_path ]]; then
            log_info "如需恢复，备份位置: $(cat /tmp/debian_upgrade_backup_path)"
        fi
        exit 1
    fi
    
    # 步骤8: 升级后优化
    log_info "步骤8/8: 升级后优化"
    post_upgrade_optimization
    
    # 验证升级结果
    if verify_upgrade "$next_version"; then
        local upgrade_end_time=$(date)
        echo
        log_success "========================================="
        log_success "🎉 升级完成！Debian $current_version → $next_version"
        log_success "========================================="
        echo
        
        # 显示详细的升级摘要
        log_info "📊 升级摘要:"
        log_info "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
        log_info "- 原版本: Debian $current_version ($current_codename) [$current_status]"
        log_info "- 新版本: Debian $next_version ($next_codename) [$next_status]"
        log_info "- 升级风险: $risk_level"
        log_info "- 开始时间: $upgrade_start_time"
        log_info "- 完成时间: $upgrade_end_time"
        log_info "- 配置备份: $(cat /tmp/debian_upgrade_backup_path 2>/dev/null || echo '未知')"
        log_info "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
        
        echo
        log_info "📝 重要提醒："
        log_info "1. 🔄 建议重启系统以确保所有更改生效"
        log_info "2. 🔧 重启后可以再次运行此脚本继续升级到更新版本"
        log_info "3. 🛡️  如遇问题，可使用备份配置进行恢复"
        log_info "4. 📚 查看 /var/log/apt/ 中的日志了解详细信息"
        
        # 检查是否还有更高版本可升级
        local further_version=$(get_next_version "$next_version")
        if [[ -n "$further_version" ]]; then
            local further_info=$(get_version_info "$further_version")
            local further_codename=$(echo "$further_info" | cut -d'|' -f1)
            local further_status=$(echo "$further_info" | cut -d'|' -f2)
            
            echo
            log_info "🚀 后续升级选项："
            if [[ "$further_status" == "stable" ]]; then
                log_info "- 可以继续升级到 Debian $further_version ($further_codename) [$further_status]"
            elif [[ "${STABLE_ONLY:-}" != "1" ]]; then
                log_info "- 可选升级到 Debian $further_version ($further_codename) [$further_status] (需要 --allow-testing)"
            fi
        fi
        
        echo
        if [[ "${FORCE:-}" == "1" ]]; then
            log_info "强制模式已启用，建议手动重启系统"
        else
            read -p "是否现在重启系统? [y/N]: " -n 1 -r </dev/tty
            echo
            if [[ $REPLY =~ ^[Yy]$ ]]; then
                log_info "🔄 正在重启系统..."
                sleep 2
                $USE_SUDO reboot
            else
                log_info "请稍后手动重启系统: sudo reboot"
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

📖 用法: $0 [选项]

🔧 选项:
  -h, --help          显示此帮助信息
  -v, --version       显示当前Debian版本信息
  -c, --check         检查是否有可用升级
  -d, --debug         启用调试模式
  --fix-only          仅执行系统修复，不进行升级
  --force             强制执行升级（跳过确认）
  --stable-only       仅升级到稳定版本，跳过测试版本
  --allow-testing     允许升级到测试版本（默认行为）

✨ 功能特性:
  ✅ 自动检测当前Debian版本和目标版本
  ✅ 逐级安全升级，避免跨版本问题
  ✅ 智能软件源选择和镜像优化
  ✅ VPS环境适配和问题修复
  ✅ 分阶段升级减少风险
  ✅ 完整的配置备份和恢复
  ✅ 网络和系统环境检查
  ✅ 详细的日志和错误处理
  ✅ 智能版本控制和风险提示
  ✅ 升级后系统优化
  ✅ 增强的GPG密钥管理
  ✅ 多重备份和故障恢复

🔄 支持的升级路径:
  • Debian 8 (Jessie) → 9 (Stretch) → 10 (Buster)
  • Debian 10 (Buster) → 11 (Bullseye) → 12 (Bookworm)
  • Debian 12 (Bookworm) → 13 (Trixie) [测试版本]

💻 示例:
  $0                    # 执行自动升级
  $0 --check            # 检查可用升级
  $0 --version          # 显示版本信息
  $0 --fix-only         # 仅修复系统问题
  $0 --debug            # 启用调试模式
  $0 --stable-only      # 仅升级到稳定版本
  $0 --force            # 强制升级（跳过确认）
  
⚠️  注意事项:
  • 升级前会自动备份重要配置
  • 建议在升级前创建系统快照
  • VPS用户请确保有控制台访问权限
  • 测试版本升级需要明确确认
  • 升级过程可能需要较长时间

🛡️  安全提示:
  • Debian 12 是当前稳定版本，建议保持使用
  • Debian 13 为测试版本，不建议生产环境使用
  • 使用 --stable-only 可避免意外升级到测试版本
  • 始终确保有可靠的备份和恢复方案
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
    echo "🔍 Debian升级检查"
    echo "========================================="
    echo "当前版本: Debian $current_version ($current_codename) [$current_status]"
    
    if [[ -z "$next_version" ]]; then
        if [[ "$current_status" == "stable" ]]; then
            echo "状态: ✅ 已是最新稳定版本"
            if [[ "${STABLE_ONLY:-}" != "1" ]]; then
                echo
                echo "💡 说明："
                echo "- 当前使用最新稳定版本，建议保持"
                echo "- 如需体验新功能，可添加 --allow-testing 选项"
                echo "- 测试版本风险较高，仅建议测试环境使用"
            fi
        else
            echo "状态: ✅ 已是最新版本 ($current_status)"
        fi
    else
        local next_version_info=$(get_version_info "$next_version")
        
        if [[ "$next_codename" == "unknown" ]]; then
            echo "状态: ✅ 已是最新稳定版本"
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
    echo "🔧 系统状态检查:"
    
    # 磁盘空间
    local disk_usage=$(df -h / | awk 'NR==2 {print $5}')
    local available_space=$(df / | awk 'NR==2 {print $4}')
    echo "- 磁盘使用: $disk_usage"
    if [[ $available_space -lt 2097152 ]]; then
        echo "  ⚠️  可用空间不足2GB"
    else
        echo "  ✅ 磁盘空间充足"
    fi
    
    # 内存状态
    local memory_info=$(free -h | awk 'NR==2{printf "使用: %s/%s", $3,$2}')
    echo "- 内存状态: $memory_info"
    
    # 网络连接
    if ping -c 1 deb.debian.org >/dev/null 2>&1; then
        echo "- 网络连接: ✅ 正常"
    else
        echo "- 网络连接: ⚠️  无法连接到Debian官方源"
    fi
    
    # VPS环境检测
    if detect_vps_environment >/dev/null 2>&1; then
        echo "- 环境类型: 🖥️  VPS/虚拟机"
    else
        echo "- 环境类型: 💻 物理机或未知"
    fi
    
    # 系统负载
    local load_avg=$(uptime | awk -F'load average:' '{print $2}' | awk '{print $1}' | tr -d ',')
    echo "- 系统负载: $load_avg"
    
    # 检查是否有损坏的包
    local broken_packages=$(dpkg --get-selections | grep -c "deinstall" 2>/dev/null || echo "0")
    if [[ $broken_packages -gt 0 ]]; then
        echo "- 软件包状态: ⚠️  发现 $broken_packages 个问题包"
    else
        echo "- 软件包状态: ✅ 正常"
    fi
    
    echo "========================================="
    
    # 升级建议
    echo "📝 升级建议:"
    if [[ -n "$next_version" && "$next_codename" != "unknown" ]]; then
        local next_version_info=$(get_version_info "$next_version")
        local next_status=$(echo "$next_version_info" | cut -d'|' -f2)
        
        if [[ "$next_status" == "stable" ]]; then
            echo "✅ 推荐升级到 Debian $next_version - 稳定版本"
            echo "🚀 执行命令: $0"
        elif [[ "$next_status" == "testing" ]]; then
            echo "⚠️  可升级到 Debian $next_version - 测试版本"
            echo "🧪 测试环境: $0 --allow-testing"
            echo "🛡️  保持稳定: $0 --stable-only (推荐)"
        else
            echo "❌ 不建议升级到 Debian $next_version - 不稳定版本"
        fi
    else
        echo "✅ 当前版本已是最佳选择，无需升级"
    fi
    
    echo "========================================="
}

# 系统修复模式
fix_only_mode() {
    log_info "========================================="
    log_info "🔧 仅执行系统修复模式"
    log_info "========================================="
    
    # 修复前检查
    log_info "修复前系统检查..."
    check_system
    
    # 执行各种修复
    log_info "1/5: VPS环境问题修复"
    fix_vps_issues
    
    log_info "2/5: APT系统清理"
    enhanced_apt_cleanup
    
    log_info "3/5: 软件包列表更新"
    smart_update_packages || log_warning "软件包列表更新失败，但继续修复"
    
    log_info "4/5: 高级系统修复"
    advanced_system_repair
    
    log_info "5/5: 系统优化"
    post_upgrade_optimization
    
    log_success "========================================="
    log_success "🎉 系统修复完成"
    log_success "========================================="
    log_info "系统已优化，现在可以尝试运行正常升级"
    log_info "建议执行: $0 --check 检查升级状态"
}

# 错误恢复函数
error_recovery() {
    local exit_code=$1
    log_error "脚本执行过程中发生错误，退出码: $exit_code"
    
    # 尝试基本修复
    log_info "尝试基本错误恢复..."
    
    # 重新配置dpkg
    $USE_SUDO dpkg --configure -a 2>/dev/null || true
    
    # 修复损坏的依赖
    $USE_SUDO apt-get --fix-broken install -y 2>/dev/null || true
    
    # 清理锁定文件
    $USE_SUDO rm -f /var/lib/dpkg/lock* 2>/dev/null || true
    $USE_SUDO rm -f /var/cache/apt/archives/lock 2>/dev/null || true
    
    if [[ -f /tmp/debian_upgrade_backup_path ]]; then
        log_info "备份文件位置: $(cat /tmp/debian_upgrade_backup_path)"
        log_info "如需恢复系统，请参考备份目录中的文件"
    fi
}

# 脚本入口 - 设置环境
main() {
    # 设置LC_ALL确保编码一致性
    export LC_ALL=C
    export LANG=C
    
    # 设置错误处理
    trap 'error_recovery $?' ERR
    
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

# 清理函数
cleanup() {
    log_debug "执行清理操作..."
    
    # 清理临时文件
    rm -f /tmp/debian_upgrade_backup_path 2>/dev/null || true
    rm -f /tmp/apt_update.log 2>/dev/null || true
    
    # 重新启用可能被停止的服务
    for service in unattended-upgrades apt-daily apt-daily-upgrade; do
        if systemctl list-unit-files "$service.service" >/dev/null 2>&1; then
            if ! systemctl is-active "$service" >/dev/null 2>&1; then
                $USE_SUDO systemctl start "$service" 2>/dev/null || true
            fi
        fi
    done
}

# 注册退出时的清理函数
trap cleanup EXIT

# 脚本入口
main "$@"
