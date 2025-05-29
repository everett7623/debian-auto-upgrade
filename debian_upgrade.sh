#!/bin/bash

# Debian自动逐级升级脚本 - 增强版
# 功能：自动检测当前版本并升级到下一个版本，直到最新版本
# 适用于大部分Debian系统，包括VPS环境

set -e  # 遇到错误立即退出

# 脚本版本
SCRIPT_VERSION="3.0"

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# 配置文件路径
UPGRADE_STATE_FILE="/var/lib/debian-upgrade/state"
UPGRADE_DISABLE_FILE="/var/lib/debian-upgrade/disabled"
BACKUP_DIR="/var/backups/debian-upgrade"

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

# 初始化目录结构
init_directories() {
    $USE_SUDO mkdir -p "$(dirname "$UPGRADE_STATE_FILE")" 2>/dev/null || true
    $USE_SUDO mkdir -p "$BACKUP_DIR" 2>/dev/null || true
}

# 检查是否需要继续升级
check_upgrade_continuation() {
    # 如果存在禁用文件，直接退出
    if [[ -f "$UPGRADE_DISABLE_FILE" ]]; then
        log_debug "升级已被用户禁用"
        return 1
    fi
    
    # 检查是否有未完成的升级
    if [[ -f "$UPGRADE_STATE_FILE" ]]; then
        local last_upgrade=$(cat "$UPGRADE_STATE_FILE" 2>/dev/null || echo "")
        if [[ -n "$last_upgrade" ]]; then
            local current_version=$(get_current_version)
            local next_version=$(get_next_version "$current_version")
            
            if [[ -n "$next_version" ]]; then
                echo
                echo "========================================="
                log_info "🔄 检测到系统升级流程"
                echo "========================================="
                log_info "上次升级: $last_upgrade"
                log_info "当前版本: Debian $current_version"
                log_info "可升级到: Debian $next_version"
                echo
                
                if [[ "${AUTO_CONTINUE:-}" == "1" ]]; then
                    log_info "自动继续升级模式已启用"
                    return 0
                else
                    read -p "是否继续升级流程? [Y/n/never]: " -r response </dev/tty
                    case "$response" in
                        [Nn]*)
                            log_info "跳过本次升级"
                            return 1
                            ;;
                        [Nn][Ee][Vv][Ee][Rr])
                            log_info "已禁用自动升级提醒"
                            $USE_SUDO touch "$UPGRADE_DISABLE_FILE"
                            return 1
                            ;;
                        *)
                            log_info "继续升级流程"
                            return 0
                            ;;
                    esac
                fi
            fi
        fi
    fi
    
    return 1
}

# 保存升级状态
save_upgrade_state() {
    local state="$1"
    init_directories
    echo "$state" | $USE_SUDO tee "$UPGRADE_STATE_FILE" > /dev/null
}

# 清除升级状态
clear_upgrade_state() {
    $USE_SUDO rm -f "$UPGRADE_STATE_FILE" 2>/dev/null || true
    $USE_SUDO rm -f "$UPGRADE_DISABLE_FILE" 2>/dev/null || true
}

# 检测地理位置
detect_location() {
    local location="US"  # 默认美国
    
    # 尝试通过IP检测位置
    local ip_info=$(curl -s --connect-timeout 5 http://ipinfo.io/country 2>/dev/null || echo "")
    
    if [[ -n "$ip_info" ]]; then
        case "$ip_info" in
            CN) location="CN" ;;
            JP) location="JP" ;;
            KR) location="KR" ;;
            SG) location="SG" ;;
            HK) location="HK" ;;
            TW) location="TW" ;;
            DE) location="DE" ;;
            GB) location="GB" ;;
            FR) location="FR" ;;
            US) location="US" ;;
            *) 
                # 检查是否在亚洲
                local timezone=$(timedatectl show -p Timezone --value 2>/dev/null || echo "")
                if [[ "$timezone" =~ Asia ]]; then
                    location="ASIA"
                fi
                ;;
        esac
    fi
    
    log_debug "检测到地理位置: $location"
    echo "$location"
}

# 选择最佳镜像源
select_mirror() {
    local location=$(detect_location)
    local codename="$1"
    local mirror=""
    
    case "$location" in
        CN)
            # 中国大陆镜像源
            local mirrors=(
                "https://mirrors.tuna.tsinghua.edu.cn/debian/"
                "https://mirrors.ustc.edu.cn/debian/"
                "https://mirrors.aliyun.com/debian/"
                "https://mirrors.163.com/debian/"
                "https://mirrors.huaweicloud.com/debian/"
            )
            
            # 测试镜像源速度
            log_info "正在测试中国镜像源速度..."
            local fastest_mirror=""
            local fastest_time=999999
            
            for m in "${mirrors[@]}"; do
                local start_time=$(date +%s%N)
                if curl -s --connect-timeout 3 --max-time 5 "${m}dists/${codename}/Release" >/dev/null 2>&1; then
                    local end_time=$(date +%s%N)
                    local elapsed=$(( (end_time - start_time) / 1000000 ))
                    log_debug "镜像 $m 响应时间: ${elapsed}ms"
                    
                    if [[ $elapsed -lt $fastest_time ]]; then
                        fastest_time=$elapsed
                        fastest_mirror=$m
                    fi
                fi
            done
            
            if [[ -n "$fastest_mirror" ]]; then
                mirror=$fastest_mirror
                log_success "选择最快的镜像源: $mirror (${fastest_time}ms)"
            else
                mirror="http://deb.debian.org/debian/"
                log_warning "无法连接到中国镜像源，使用官方源"
            fi
            ;;
            
        JP)
            mirror="http://ftp.jp.debian.org/debian/"
            ;;
            
        KR)
            mirror="http://ftp.kr.debian.org/debian/"
            ;;
            
        DE)
            mirror="http://ftp.de.debian.org/debian/"
            ;;
            
        GB)
            mirror="http://ftp.uk.debian.org/debian/"
            ;;
            
        *)
            mirror="http://deb.debian.org/debian/"
            ;;
    esac
    
    echo "$mirror"
}

# 生成sources.list
generate_sources_list() {
    local version="$1"
    local codename="$2"
    local mirror=$(select_mirror "$codename")
    local security_mirror="http://security.debian.org/debian-security"
    
    # 对于中国用户，使用镜像的安全源
    if [[ "$mirror" =~ tsinghua ]]; then
        security_mirror="https://mirrors.tuna.tsinghua.edu.cn/debian-security"
    elif [[ "$mirror" =~ ustc ]]; then
        security_mirror="https://mirrors.ustc.edu.cn/debian-security"
    elif [[ "$mirror" =~ aliyun ]]; then
        security_mirror="https://mirrors.aliyun.com/debian-security"
    fi
    
    log_info "使用镜像源: $mirror"
    
    case "$version" in
        "12"|"13"|"14"|"15")
            # Debian 12+ 包含non-free-firmware
            cat << EOF
# Debian $version ($codename) sources
deb $mirror $codename main contrib non-free non-free-firmware
deb-src $mirror $codename main contrib non-free non-free-firmware

# Security updates
deb $security_mirror $codename-security main contrib non-free non-free-firmware
deb-src $security_mirror $codename-security main contrib non-free non-free-firmware

# Updates
deb $mirror $codename-updates main contrib non-free non-free-firmware
deb-src $mirror $codename-updates main contrib non-free non-free-firmware
EOF
            ;;
        "11")
            # Debian 11 使用新的安全源格式
            cat << EOF
# Debian $version ($codename) sources
deb $mirror $codename main contrib non-free
deb-src $mirror $codename main contrib non-free

# Security updates
deb $security_mirror $codename-security main contrib non-free
deb-src $security_mirror $codename-security main contrib non-free

# Updates
deb $mirror $codename-updates main contrib non-free
deb-src $mirror $codename-updates main contrib non-free
EOF
            ;;
        *)
            # Debian 10及以下版本
            cat << EOF
# Debian $version ($codename) sources
deb $mirror $codename main contrib non-free
deb-src $mirror $codename main contrib non-free

# Security updates
deb $security_mirror $codename/updates main contrib non-free
deb-src $security_mirror $codename/updates main contrib non-free

# Updates
deb $mirror $codename-updates main contrib non-free
deb-src $mirror $codename-updates main contrib non-free
EOF
            ;;
    esac
}

# 系统健康检查
system_health_check() {
    log_info "执行系统健康检查..."
    local issues=0
    
    # 检查关键服务
    local critical_services=("ssh" "networking" "systemd-resolved")
    for service in "${critical_services[@]}"; do
        if systemctl is-enabled "$service" >/dev/null 2>&1; then
            if ! systemctl is-active "$service" >/dev/null 2>&1; then
                log_warning "关键服务 $service 未运行"
                ((issues++))
            else
                log_debug "服务 $service 正常"
            fi
        fi
    done
    
    # 检查文件系统
    if [[ -f /proc/mounts ]]; then
        while read -r dev mount fstype rest; do
            if [[ "$fstype" == "ext"* || "$fstype" == "xfs" || "$fstype" == "btrfs" ]]; then
                if [[ "$mount" == "/" || "$mount" == "/boot" || "$mount" == "/var" ]]; then
                    local usage=$(df "$mount" | awk 'NR==2 {print int($5)}')
                    if [[ $usage -gt 90 ]]; then
                        log_warning "分区 $mount 使用率过高: ${usage}%"
                        ((issues++))
                    else
                        log_debug "分区 $mount 使用率: ${usage}%"
                    fi
                fi
            fi
        done < /proc/mounts
    fi
    
    # 检查系统负载
    local load_avg=$(uptime | awk -F'load average:' '{print $2}' | awk '{print $1}' | tr -d ',')
    local cpu_count=$(nproc)
    # 使用 awk 替代 bc 进行浮点数比较
    local threshold=$((cpu_count * 2))
    if awk -v load="$load_avg" -v thresh="$threshold" 'BEGIN { exit (load > thresh) ? 0 : 1 }'; then
        log_warning "系统负载过高: $load_avg (CPU数: $cpu_count)"
        ((issues++))
    else
        log_debug "系统负载正常: $load_avg"
    fi
    
    # 检查内存
    local mem_available=$(free -m | awk 'NR==2{print $7}')
    if [[ $mem_available -lt 256 ]]; then
        log_warning "可用内存过低: ${mem_available}MB"
        ((issues++))
    else
        log_debug "可用内存充足: ${mem_available}MB"
    fi
    
    # 检查包管理器状态
    if ! dpkg --audit >/dev/null 2>&1; then
        log_warning "发现未配置完成的软件包"
        ((issues++))
    else
        log_debug "软件包状态正常"
    fi
    
    if [[ $issues -gt 0 ]]; then
        log_warning "发现 $issues 个潜在问题"
        if [[ $issues -gt 2 ]]; then
            log_error "系统存在较多问题，建议先修复再升级"
            if [[ "${FORCE:-}" != "1" ]]; then
                read -p "是否继续升级? [y/N]: " -n 1 -r </dev/tty
                echo
                if [[ ! $REPLY =~ ^[Yy]$ ]]; then
                    return 1
                fi
            fi
        fi
    else
        log_success "系统健康检查通过"
    fi
    
    return 0
}

# 创建系统快照
create_system_snapshot() {
    local snapshot_name="debian-upgrade-$(date +%Y%m%d-%H%M%S)"
    
    log_info "创建系统快照..."
    
    # 备份关键配置文件
    local backup_files=(
        "/etc/apt/sources.list"
        "/etc/apt/sources.list.d"
        "/etc/network/interfaces"
        "/etc/NetworkManager/system-connections"
        "/etc/fstab"
        "/etc/hostname"
        "/etc/hosts"
        "/etc/resolv.conf"
        "/etc/ssh/sshd_config"
        "/etc/sudoers"
        "/etc/sysctl.conf"
        "/etc/security/limits.conf"
    )
    
    # 创建备份目录
    local snapshot_dir="$BACKUP_DIR/$snapshot_name"
    $USE_SUDO mkdir -p "$snapshot_dir"
    
    # 备份文件
    for file in "${backup_files[@]}"; do
        if [[ -e "$file" ]]; then
            local dir=$(dirname "$file")
            $USE_SUDO mkdir -p "$snapshot_dir$dir"
            $USE_SUDO cp -a "$file" "$snapshot_dir$file" 2>/dev/null || true
        fi
    done
    
    # 保存系统信息
    $USE_SUDO dpkg --get-selections > "$snapshot_dir/dpkg-selections.txt"
    $USE_SUDO apt-mark showmanual > "$snapshot_dir/manually-installed.txt"
    
    # 保存系统版本信息
    cat /etc/os-release > "$snapshot_dir/os-release"
    uname -a > "$snapshot_dir/kernel-info.txt"
    
    # 创建恢复脚本
    cat << 'EOF' | $USE_SUDO tee "$snapshot_dir/restore.sh" > /dev/null
#!/bin/bash
# 系统恢复脚本

SNAPSHOT_DIR="$(dirname "$0")"

echo "开始恢复系统配置..."

# 恢复配置文件
for file in $(find "$SNAPSHOT_DIR" -type f ! -name "*.txt" ! -name "*.sh" ! -name "os-release" | sed "s|$SNAPSHOT_DIR||"); do
    if [[ -f "$SNAPSHOT_DIR$file" ]]; then
        echo "恢复: $file"
        cp -a "$SNAPSHOT_DIR$file" "$file"
    fi
done

echo "配置文件恢复完成"
echo "如需恢复软件包状态，请运行："
echo "dpkg --set-selections < $SNAPSHOT_DIR/dpkg-selections.txt"
echo "apt-get dselect-upgrade"
EOF
    
    $USE_SUDO chmod +x "$snapshot_dir/restore.sh"
    
    log_success "系统快照已创建: $snapshot_dir"
    echo "$snapshot_dir" > "$BACKUP_DIR/latest-snapshot"
    
    return 0
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
    if ! ping -c 1 -W 3 8.8.8.8 >/dev/null 2>&1; then
        log_warning "网络连接可能存在问题"
        
        # 尝试修复DNS
        if [[ ! -f /etc/resolv.conf ]] || [[ ! -s /etc/resolv.conf ]]; then
            log_info "尝试修复DNS配置..."
            echo "nameserver 8.8.8.8" | $USE_SUDO tee /etc/resolv.conf > /dev/null
            echo "nameserver 8.8.4.4" | $USE_SUDO tee -a /etc/resolv.conf > /dev/null
        fi
    fi
    
    # 检查磁盘空间
    local available_space=$(df / | awk 'NR==2 {print $4}')
    if [[ $available_space -lt 2097152 ]]; then  # 2GB
        log_warning "根分区可用空间不足2GB，升级过程中可能出现空间不足"
        
        # 尝试清理空间
        log_info "尝试清理磁盘空间..."
        $USE_SUDO apt-get clean 2>/dev/null || true
        $USE_SUDO apt-get autoclean 2>/dev/null || true
        
        # 清理旧内核
        if command -v purge-old-kernels >/dev/null 2>&1; then
            $USE_SUDO purge-old-kernels --keep 2 -y 2>/dev/null || true
        fi
        
        # 重新检查
        available_space=$(df / | awk 'NR==2 {print $4}')
        if [[ $available_space -lt 1048576 ]]; then  # 1GB
            log_error "磁盘空间严重不足，请先清理空间"
            exit 1
        fi
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
        log_warning "检测到以root用户运行"
        USE_SUDO=""
    else
        if ! sudo -n true 2>/dev/null; then
            log_info "需要sudo权限来执行升级操作"
            sudo -v
        fi
        USE_SUDO="sudo"
    fi
}

# 改进版本检测
get_current_version() {
    local version_id=""
    local debian_version=""
    
    log_debug "开始检测Debian版本..."
    
    # 方法1: 从os-release获取版本
    if [[ -f /etc/os-release ]]; then
        version_id=$(grep "^VERSION_ID=" /etc/os-release | cut -d'"' -f2 2>/dev/null || echo "")
        log_debug "从os-release获取版本: '$version_id'"
    fi
    
    # 方法2: 从debian_version推断
    if [[ -f /etc/debian_version ]]; then
        debian_version=$(cat /etc/debian_version 2>/dev/null || echo "")
        log_debug "debian_version内容: '$debian_version'"
        
        # 更精确的版本匹配
        case "$debian_version" in
            8.*|jessie*) local detected_version="8" ;;
            9.*|stretch*) local detected_version="9" ;;
            10.*|buster*) local detected_version="10" ;;
            11.*|bullseye*) local detected_version="11" ;;
            12.*|bookworm*) local detected_version="12" ;;
            13.*|trixie*) local detected_version="13" ;;
            14.*|forky*) local detected_version="14" ;;
            *) local detected_version="" ;;
        esac
        
        # 如果os-release没有VERSION_ID，使用推断的版本
        if [[ -z "$version_id" && -n "$detected_version" ]]; then
            version_id="$detected_version"
            log_debug "从debian_version推断版本: '$version_id'"
        fi
    fi
    
    # 方法3: 从lsb_release获取（如果可用）
    if [[ -z "$version_id" ]] && command -v lsb_release >/dev/null 2>&1; then
        local lsb_release=$(lsb_release -rs 2>/dev/null | cut -d. -f1)
        if [[ -n "$lsb_release" && "$lsb_release" =~ ^[0-9]+$ ]]; then
            version_id="$lsb_release"
            log_debug "从lsb_release获取版本: '$version_id'"
        fi
    fi
    
    # 方法4: 从APT策略检测
    if [[ -z "$version_id" ]]; then
        local apt_policy=$(apt-cache policy base-files 2>/dev/null | head -10)
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
        log_debug "从APT策略检测版本: '$version_id'"
    fi
    
    # 最终验证
    if [[ -z "$version_id" ]] || [[ ! "$version_id" =~ ^[0-9]+$ ]]; then
        log_error "无法确定Debian版本"
        log_error "调试信息："
        log_error "- /etc/debian_version: '$debian_version'"
        log_error "- /etc/os-release VERSION_ID: '$(grep VERSION_ID /etc/os-release 2>/dev/null || echo '未找到')'"
        log_error "- 内核版本: $(uname -r)"
        exit 1
    fi
    
    log_debug "最终检测版本: '$version_id'"
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
  --continue          自动继续之前的升级流程
  --rollback          回滚到最近的系统快照
  --clear-state       清除升级状态和禁用标记

✨ 新增功能:
  ✅ 智能镜像源选择（根据地理位置）
  ✅ 系统健康检查
  ✅ 完整系统快照和回滚功能
  ✅ 重启后继续升级提示
  ✅ 用户可永久禁用升级提醒

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
  $0 --continue         # 自动继续升级流程
  $0 --rollback         # 回滚系统
  $0 --clear-state      # 清除升级状态
  
⚠️  注意事项:
  • 升级前会自动创建系统快照
  • 建议在升级前确保有控制台访问权限
  • VPS用户请确保有控制台访问权限
  • 测试版本升级需要明确确认
  • 升级过程可能需要较长时间

🛡️  安全提示:
  • Debian 12 是当前稳定版本，建议保持使用
  • Debian 13 为测试版本，不建议生产环境使用
  • 使用 --stable-only 可避免意外升级到测试版本
  • 每次升级都会创建快照，可随时回滚
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
        local next_codename=$(echo "$next_version_info" | cut -d'|' -f1)
        local next_status=$(echo "$next_version_info" | cut -d'|' -f2)
        
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
    if ping -c 1 -W 3 8.8.8.8 >/dev/null 2>&1; then
        echo "- 网络连接: ✅ 正常"
    else
        echo "- 网络连接: ⚠️  可能存在问题"
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
    
    # 检查升级状态
    if [[ -f "$UPGRADE_STATE_FILE" ]]; then
        echo "- 升级状态: 🔄 有进行中的升级流程"
    elif [[ -f "$UPGRADE_DISABLE_FILE" ]]; then
        echo "- 升级状态: 🚫 升级提醒已禁用"
    else
        echo "- 升级状态: ✅ 正常"
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

# 系统回滚功能
rollback_system() {
    log_info "========================================="
    log_info "🔙 系统回滚功能"
    log_info "========================================="
    
    if [[ ! -f "$BACKUP_DIR/latest-snapshot" ]]; then
        log_error "未找到可用的系统快照"
        exit 1
    fi
    
    local latest_snapshot=$(cat "$BACKUP_DIR/latest-snapshot")
    if [[ ! -d "$latest_snapshot" ]]; then
        log_error "快照目录不存在: $latest_snapshot"
        exit 1
    fi
    
    log_info "找到最近的快照: $latest_snapshot"
    log_warning "回滚将恢复以下配置："
    echo "- APT源配置"
    echo "- 网络配置"
    echo "- 系统配置文件"
    echo
    
    if [[ "${FORCE:-}" != "1" ]]; then
        read -p "确认要回滚系统吗? [y/N]: " -n 1 -r </dev/tty
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            log_info "取消回滚"
            exit 0
        fi
    fi
    
    log_info "开始回滚系统..."
    
    # 执行回滚脚本
    if [[ -f "$latest_snapshot/restore.sh" ]]; then
        $USE_SUDO bash "$latest_snapshot/restore.sh"
        log_success "系统配置已回滚"
        
        # 更新APT
        log_info "更新软件包列表..."
        $USE_SUDO apt-get update || true
        
        log_success "回滚完成"
        log_info "如需恢复软件包状态，请运行："
        echo "sudo dpkg --set-selections < $latest_snapshot/dpkg-selections.txt"
        echo "sudo apt-get dselect-upgrade"
    else
        log_error "回滚脚本不存在"
        exit 1
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
    
    if [[ -z "$next_version" ]]; then
        if [[ "$current_status" == "stable" ]]; then
            log_success "🎉 恭喜！您已经在使用最新稳定版本的Debian $current_version"
            echo
            log_info "💡 提示："
            log_info "- 当前版本是最新的稳定版本，建议保持使用"
            if [[ "${STABLE_ONLY:-}" != "1" ]]; then
                log_info "- 如需体验新功能，可使用 --allow-testing 选项升级到测试版本"
                log_info "- 测试版本可能不稳定，不建议在生产环境使用"
            fi
        else
            log_info "您正在使用 Debian $current_version ($current_status)"
            if [[ "$current_status" == "testing" || "$current_status" == "unstable" ]]; then
                log_info "当前版本为非稳定版本，如需回到稳定版本请手动操作"
            fi
        fi
        
        # 清除升级状态
        clear_upgrade_state
        exit 0
    fi
    
    local next_version_info=$(get_version_info "$next_version")
    local next_codename=$(echo "$next_version_info" | cut -d'|' -f1)
    local next_status=$(echo "$next_version_info" | cut -d'|' -f2)
    
    if [[ "$next_codename" == "unknown" ]]; then
        log_warning "下一个版本 Debian $next_version 可能还未发布或不被支持"
        log_info "当前版本 Debian $current_version 可能已经是最新的稳定版本"
        clear_upgrade_state
        exit 0
    fi
    
    log_info "🎯 准备升级到: Debian $next_version ($next_codename) [$next_status]"
    
    # 执行系统健康检查
    if ! system_health_check; then
        log_error "系统健康检查未通过，请先解决问题"
        exit 1
    fi
    
    # 创建系统快照
    create_system_snapshot
    
    # 风险提示
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
        
        if [[ "${FORCE:-}" == "1" ]]; then
            log_warning "强制模式已启用，跳过确认直接升级"
        else
            if get_user_confirmation "您确定要升级到测试版本吗？请输入 'YES' 确认，或 'no' 取消: "; then
                log_info "✅ 用户确认升级到测试版本"
            else
                log_info "❌ 用户取消升级"
                log_success "保持当前稳定版本 Debian $current_version - 明智的选择！"
                clear_upgrade_state
                exit 0
            fi
        fi
        echo
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
                clear_upgrade_state
                exit 0
            fi
        fi
    fi
    
    # 保存升级状态
    save_upgrade_state "升级中: $current_version -> $next_version @ $(date)"
    
    log_info "🚀 开始升级过程..."
    
    # 升级步骤
    log_info "步骤1: 更新软件源配置"
    
    # 备份sources.list
    $USE_SUDO cp /etc/apt/sources.list /etc/apt/sources.list.backup.$(date +%s) 2>/dev/null || true
    
    # 生成新的sources.list到临时文件
    local temp_sources="/tmp/sources.list.$"
    generate_sources_list "$next_version" "$next_codename" > "$temp_sources"
    
    # 验证临时文件内容
    if [[ -s "$temp_sources" ]]; then
        # 移动到正确位置
        $USE_SUDO mv "$temp_sources" /etc/apt/sources.list
        log_success "软件源配置已更新"
    else
        log_error "生成软件源配置失败"
        rm -f "$temp_sources"
        exit 1
    fi
    
    log_info "步骤2: 更新软件包列表"
    if ! $USE_SUDO apt-get update; then
        log_error "更新软件包列表失败"
        log_info "尝试使用备用镜像源..."
        
        # 尝试官方源
        generate_sources_list "$next_version" "$next_codename" | sed 's|https://|http://|g' | $USE_SUDO tee /etc/apt/sources.list > /dev/null
        
        if ! $USE_SUDO apt-get update; then
            log_error "无法更新软件包列表，请检查网络连接"
            exit 1
        fi
    fi
    
    log_info "步骤3: 执行系统升级"
    
    # 分阶段升级
    log_info "3.1: 最小升级"
    DEBIAN_FRONTEND=noninteractive $USE_SUDO apt-get upgrade -y \
        -o Dpkg::Options::="--force-confdef" \
        -o Dpkg::Options::="--force-confold" || {
        log_warning "最小升级失败，继续尝试完整升级"
    }
    
    log_info "3.2: 完整升级"
    DEBIAN_FRONTEND=noninteractive $USE_SUDO apt-get dist-upgrade -y \
        -o Dpkg::Options::="--force-confdef" \
        -o Dpkg::Options::="--force-confold" || {
        log_error "系统升级失败"
        log_info "建议运行 --rollback 回滚到升级前状态"
        exit 1
    }
    
    log_info "步骤4: 清理系统"
    $USE_SUDO apt-get autoremove -y --purge 2>/dev/null || true
    $USE_SUDO apt-get autoclean 2>/dev/null || true
    
    # 验证升级结果
    sleep 3
    local new_version=$(get_current_version)
    if [[ "$new_version" == "$next_version" ]]; then
        echo
        log_success "========================================="
        log_success "🎉 升级完成！Debian $current_version → $next_version"
        log_success "========================================="
        echo
        log_info "📝 重要提醒："
        log_info "1. 🔄 建议重启系统以确保所有更改生效"
        log_info "2. 🔧 重启后可以再次运行此脚本继续升级到更新版本"
        log_info "3. 🛡️  如遇问题，可使用 --rollback 进行系统回滚"
        
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
                log_info "- 重启后运行脚本将提示是否继续升级"
            elif [[ "${STABLE_ONLY:-}" != "1" ]]; then
                log_info "- 可选升级到 Debian $further_version ($further_codename) [$further_status] (需要 --allow-testing)"
            fi
            
            # 保存升级状态以便重启后继续
            save_upgrade_state "已完成: $current_version -> $next_version @ $(date)"
        else
            # 升级完成，清除状态
            clear_upgrade_state
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
        log_error "期望版本: Debian $next_version"
        log_error "检测版本: Debian $new_version"
        log_info "建议运行 --rollback 回滚系统"
        exit 1
    fi
}

# 系统修复模式
fix_only_mode() {
    log_info "========================================="
    log_info "🔧 仅执行系统修复模式"
    log_info "========================================="
    
    log_info "1/5: 清理APT锁定文件"
    $USE_SUDO rm -f /var/lib/dpkg/lock-frontend 2>/dev/null || true
    $USE_SUDO rm -f /var/lib/dpkg/lock 2>/dev/null || true
    $USE_SUDO rm -f /var/cache/apt/archives/lock 2>/dev/null || true
    $USE_SUDO rm -f /var/lib/apt/lists/lock 2>/dev/null || true
    
    log_info "2/5: 修复dpkg状态"
    $USE_SUDO dpkg --configure -a 2>/dev/null || true
    
    log_info "3/5: 修复依赖关系"
    $USE_SUDO apt-get --fix-broken install -y 2>/dev/null || true
    
    log_info "4/5: 清理无用包"
    $USE_SUDO apt-get autoremove -y 2>/dev/null || true
    $USE_SUDO apt-get autoclean 2>/dev/null || true
    
    log_info "5/5: 更新软件包列表"
    $USE_SUDO apt-get update || log_warning "软件包列表更新失败，但系统修复已完成"
    
    # 执行健康检查
    system_health_check
    
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
    
    log_info "基本错误恢复完成"
    log_info "建议运行以下命令进行深度修复："
    echo "  $0 --fix-only    # 执行完整系统修复"
    echo "  $0 --rollback    # 回滚到升级前状态"
}

# 脚本入口
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
                echo "升级脚本版本: v$SCRIPT_VERSION"
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
            --continue)
                export AUTO_CONTINUE=1
                log_info "自动继续升级模式已启用"
                shift
                ;;
            --rollback)
                check_root
                rollback_system
                exit 0
                ;;
            --clear-state)
                check_root
                clear_upgrade_state
                log_success "升级状态已清除"
                exit 0
                ;;
            *)
                log_error "未知选项: $1"
                echo "使用 '$0 --help' 查看帮助信息"
                exit 1
                ;;
        esac
    done
    
    # 检查权限
    check_root
    
    # 初始化目录
    init_directories
    
    # 检查是否需要继续之前的升级
    if check_upgrade_continuation; then
        check_system
        main_upgrade
    else
        # 默认执行升级
        check_system
        main_upgrade
    fi
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

# 检查是否为直接执行脚本（不是被source）
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    # 脚本入口 - 只有直接执行时才调用main函数
    main "$@"
fi
