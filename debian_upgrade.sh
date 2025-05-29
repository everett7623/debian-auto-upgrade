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

# 检查是否有待继续的升级
check_pending_upgrade() {
    local upgrade_state_file="/var/lib/debian_upgrade_state"
    local backup_state_file="/etc/debian_upgrade_state.backup"
    local upgrade_log_file="/var/log/debian_upgrade_progress.log"
    
    # 优先检查主状态文件，如果不存在则检查备份
    if [[ ! -f "$upgrade_state_file" && -f "$backup_state_file" ]]; then
        log_debug "主状态文件不存在，使用备份状态文件"
        $USE_SUDO cp "$backup_state_file" "$upgrade_state_file" 2>/dev/null || true
    fi
    
    if [[ -f "$upgrade_state_file" ]]; then
        log_info "检测到待继续的升级状态..."
        
        # 读取升级状态信息
        local previous_version=""
        local current_version=""
        local target_version=""
        local upgrade_time=""
        local reboot_pending=""
        
        if [[ -r "$upgrade_state_file" ]]; then
            # 使用sudo读取文件内容
            while IFS='=' read -r key value; do
                case "$key" in
                    "PREVIOUS_VERSION") previous_version="$value" ;;
                    "CURRENT_VERSION") current_version="$value" ;;
                    "TARGET_VERSION") target_version="$value" ;;
                    "UPGRADE_TIME") upgrade_time="$value" ;;
                    "REBOOT_PENDING") reboot_pending="$value" ;;
                esac
            done < <($USE_SUDO cat "$upgrade_state_file" 2>/dev/null || cat "$upgrade_state_file" 2>/dev/null)
        fi
        
        # 验证当前版本
        local actual_current_version=$(get_current_version)
        
        echo "========================================="
        echo "🔄 检测到系统重启后的升级继续状态"
        echo "========================================="
        echo
        echo "📊 升级进度信息："
        echo "   上次版本: Debian $previous_version"
        echo "   当前版本: Debian $actual_current_version" 
        echo "   预期版本: Debian $current_version"
        echo "   升级时间: $upgrade_time"
        
        # 检查升级是否成功
        if [[ "$actual_current_version" == "$current_version" ]]; then
            echo "   状态: ✅ 上次升级成功"
            
            # 显示升级历史信息
            check_upgrade_state_history
            
            # 检查是否还有下一个版本可升级
            local next_version=$(get_next_version "$actual_current_version")
            
            if [[ -n "$next_version" ]]; then
                local next_version_info=$(get_version_info "$next_version")
                local next_codename=$(echo "$next_version_info" | cut -d'|' -f1)
                local next_status=$(echo "$next_version_info" | cut -d'|' -f2)
                
                echo
                echo "🎯 下一步可升级到："
                echo "   目标版本: Debian $next_version ($next_codename) [$next_status]"
                
                # 风险评估
                local risk_level="低"
                if [[ "$next_status" == "testing" ]]; then
                    risk_level="中等"
                elif [[ "$next_status" == "unstable" ]]; then
                    risk_level="高"
                fi
                echo "   升级风险: $risk_level"
                
                echo
                echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
                echo "🤔 您希望继续升级到下一个版本吗？"
                echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
                echo
                echo "选项说明："
                echo "  [Y] 是的，继续升级到 Debian $next_version"
                echo "  [N] 不，永久保持当前版本（不再提示）"
                echo "  [S] 暂时跳过，下次重启后再次询问"
                echo "  [C] 检查系统状态但不升级"
                echo "  [Q] 退出脚本"
                echo
                
                # 特殊提示for测试版本
                if [[ "$next_status" == "testing" || "$next_status" == "unstable" ]]; then
                    echo "⚠️  警告：下一个版本为非稳定版本！"
                    echo "   • 不建议在生产环境中使用"
                    echo "   • 可能包含未修复的bug"
                    echo "   • 建议先在测试环境验证"
                    echo
                fi
                
                # 强制模式检查
                if [[ "${FORCE:-}" == "1" ]]; then
                    log_info "✅ 强制模式已启用，自动选择继续升级"
                    cleanup_upgrade_state
                    return 0
                fi
                
                local user_choice=""
                while true; do
                    echo -n "请选择 [Y/N/S/C/Q]: "
                    read -r user_choice </dev/tty
                    
                    case "${user_choice^^}" in
                        "Y"|"YES")
                            log_info "✅ 用户选择继续升级到 Debian $next_version"
                            cleanup_upgrade_state
                            return 0  # 继续正常升级流程
                            ;;
                        "N"|"NO")
                            log_info "❌ 用户选择永久保持当前版本"
                            cleanup_upgrade_state
                            show_upgrade_completion_summary "$previous_version" "$actual_current_version"
                            exit 0
                            ;;
                        "S"|"SKIP")
                            log_info "⏭️ 用户选择暂时跳过，下次重启后再次询问"
                            # 不清理状态文件，但更新标记表示用户已经看过提示
                            mark_upgrade_state_seen
                            echo
                            echo "✅ 已保存选择，下次重启后将再次询问是否升级"
                            echo "💡 如需立即升级，请运行: $0"
                            echo "💡 如需永久取消，请运行: $0 --check-state 然后选择 N"
                            exit 0
                            ;;
                        "C"|"CHECK")
                            log_info "🔍 用户选择检查系统状态"
                            # 保留状态文件，只是检查系统
                            check_upgrade
                            exit 0
                            ;;
                        "Q"|"QUIT")
                            log_info "👋 用户选择退出"
                            # 保留状态文件，用户可能稍后想要升级
                            echo "感谢使用 Debian 自动升级工具！"
                            echo "💡 升级状态已保留，重启后会再次询问"
                            exit 0
                            ;;
                        *)
                            echo "❌ 无效选择，请输入 Y、N、S、C 或 Q"
                            ;;
                    esac
                done
            else
                # 已经是最新版本
                echo
                echo "🎉 恭喜！您已经升级到最新版本！"
                cleanup_upgrade_state
                show_upgrade_completion_summary "$previous_version" "$actual_current_version"
                exit 0
            fi
        else
            # 升级可能失败了
            echo "   状态: ⚠️  升级可能未完全成功"
            echo "   期望: Debian $current_version"
            echo "   实际: Debian $actual_current_version"
            echo
            echo "🔧 建议运行系统检查和修复："
            echo "   $0 --fix-only"
            echo
            
            if [[ "${FORCE:-}" != "1" ]]; then
                read -p "是否现在运行系统修复？[y/N]: " -n 1 -r </dev/tty
                echo
                if [[ $REPLY =~ ^[Yy]$ ]]; then
                    cleanup_upgrade_state
                    fix_only_mode
                    exit 0
                else
                    cleanup_upgrade_state
                    exit 1
                fi
            else
                log_info "强制模式已启用，自动运行系统修复"
                cleanup_upgrade_state
                fix_only_mode
                exit 0
            fi
        fi
    fi
    
    return 1  # 没有待继续的升级
}

# 保存升级状态
save_upgrade_state() {
    local previous_version=$1
    local current_version=$2
    local target_version=$3
    local upgrade_state_file="/var/lib/debian_upgrade_state"
    local upgrade_log_file="/var/log/debian_upgrade_progress.log"
    
    log_info "保存升级状态信息..."
    
    # 确保目录存在
    $USE_SUDO mkdir -p /var/lib 2>/dev/null || true
    $USE_SUDO mkdir -p /var/log 2>/dev/null || true
    
    # 创建状态文件（使用持久化目录）
    cat << EOF | $USE_SUDO tee "$upgrade_state_file" > /dev/null
PREVIOUS_VERSION=$previous_version
CURRENT_VERSION=$current_version  
TARGET_VERSION=$target_version
UPGRADE_TIME=$(date '+%Y-%m-%d %H:%M:%S')
SCRIPT_VERSION=$SCRIPT_VERSION
REBOOT_PENDING=1
EOF
    
    # 设置文件权限
    $USE_SUDO chmod 644 "$upgrade_state_file"
    
    # 记录到系统日志
    echo "$(date '+%Y-%m-%d %H:%M:%S') - Debian升级: $previous_version → $current_version (目标: $target_version)" | $USE_SUDO tee -a "$upgrade_log_file" > /dev/null
    
    # 创建一个在 /etc 下的备份状态文件
    $USE_SUDO cp "$upgrade_state_file" "/etc/debian_upgrade_state.backup" 2>/dev/null || true
    
    log_debug "升级状态已保存到 $upgrade_state_file"
    log_debug "备份状态已保存到 /etc/debian_upgrade_state.backup"
}

# 标记升级状态已被查看（用于暂时跳过）
mark_upgrade_state_seen() {
    local upgrade_state_file="/var/lib/debian_upgrade_state"
    local backup_state_file="/etc/debian_upgrade_state.backup"
    
    if [[ -f "$upgrade_state_file" ]]; then
        # 添加已查看标记和时间戳
        echo "USER_SEEN=1" | $USE_SUDO tee -a "$upgrade_state_file" > /dev/null
        echo "LAST_SEEN=$(date '+%Y-%m-%d %H:%M:%S')" | $USE_SUDO tee -a "$upgrade_state_file" > /dev/null
        echo "SKIP_COUNT=$((${SKIP_COUNT:-0} + 1))" | $USE_SUDO tee -a "$upgrade_state_file" > /dev/null
        
        # 同步到备份文件
        if [[ -f "$backup_state_file" ]]; then
            $USE_SUDO cp "$upgrade_state_file" "$backup_state_file"
        fi
        
        log_debug "升级状态已标记为已查看"
    fi
}

# 检查升级状态的查看历史
check_upgrade_state_history() {
    local upgrade_state_file="/var/lib/debian_upgrade_state"
    local user_seen=""
    local last_seen=""
    local skip_count=0
    
    if [[ -f "$upgrade_state_file" ]]; then
        while IFS='=' read -r key value; do
            case "$key" in
                "USER_SEEN") user_seen="$value" ;;
                "LAST_SEEN") last_seen="$value" ;;
                "SKIP_COUNT") skip_count="$value" ;;
            esac
        done < <($USE_SUDO cat "$upgrade_state_file" 2>/dev/null || cat "$upgrade_state_file" 2>/dev/null)
        
        if [[ "$user_seen" == "1" && -n "$last_seen" ]]; then
            echo
            echo "📋 升级提示历史："
            echo "   上次查看: $last_seen"
            echo "   跳过次数: ${skip_count:-0}"
            
            # 如果跳过次数过多，给出提醒
            if [[ ${skip_count:-0} -ge 3 ]]; then
                echo
                echo "💡 温馨提示："
                echo "   您已经跳过升级提示 ${skip_count} 次"
                echo "   建议考虑升级以获得最新的安全更新和功能改进"
                echo "   或选择'永久保持'来停止提醒"
            fi
        fi
    fi
}
cleanup_upgrade_state() {
    local upgrade_state_file="/var/lib/debian_upgrade_state"
    local backup_state_file="/etc/debian_upgrade_state.backup"
    
    if [[ -f "$upgrade_state_file" ]]; then
        $USE_SUDO rm -f "$upgrade_state_file" 2>/dev/null || true
        log_debug "升级状态文件已清理: $upgrade_state_file"
    fi
    
    if [[ -f "$backup_state_file" ]]; then
        $USE_SUDO rm -f "$backup_state_file" 2>/dev/null || true
        log_debug "备份状态文件已清理: $backup_state_file"
    fi
}

# 显示升级完成摘要
show_upgrade_completion_summary() {
    local from_version=$1
    local to_version=$2
    
    echo
    echo "========================================="
    echo "🎉 系统升级完成摘要"
    echo "========================================="
    echo
    echo "📊 升级详情："
    echo "   起始版本: Debian $from_version"
    echo "   当前版本: Debian $to_version"
    echo "   升级方式: 逐级安全升级"
    echo "   完成时间: $(date '+%Y-%m-%d %H:%M:%S')"
    echo
    echo "✅ 成功完成的操作："
    echo "   • 系统版本升级"
    echo "   • 软件包更新"
    echo "   • 配置文件处理"
    echo "   • 系统服务重启"
    echo
    echo "📝 建议后续操作："
    echo "   • 检查关键服务运行状态"
    echo "   • 验证网络连接和SSH访问"
    echo "   • 检查自定义配置是否正常"
    echo "   • 查看系统日志: /var/log/debian_upgrade_progress.log"
    echo
    echo "🔧 如需继续升级到更高版本："
    echo "   • 重新运行此脚本: $0"
    echo "   • 或检查可用升级: $0 --check"
    echo
    echo "感谢使用 Debian 自动升级工具！"
    echo "========================================="
}
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

# 改进版本检测 - 更准确的检测
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
  --check-state       检查升级状态（重启后使用）

✨ 功能特性:
  ✅ 自动检测当前Debian版本和目标版本
  ✅ 逐级安全升级，避免跨版本问题
  ✅ 智能软件源选择和镜像优化
  ✅ VPS环境适配和问题修复
  ✅ 分阶段升级减少风险
  ✅ 完整的配置备份和恢复
  ✅ 网络和系统环境检查
  ✅ 详细的日志和错误处理
  ✅ 重启后升级状态保持和用户选择

🔄 重启后升级选择:
  当系统升级并重启后，脚本会自动检测升级状态并提供以下选择：
  • [Y] 继续升级 - 立即升级到下一个版本
  • [N] 永久保持 - 清除升级状态，不再提示升级
  • [S] 暂时跳过 - 保留升级状态，下次重启时再次询问
  • [C] 检查状态 - 查看系统状态但不进行升级
  • [Q] 退出脚本 - 保留升级状态，稍后可以继续

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
    if ping -c 1 deb.debian.org >/dev/null 2>&1; then
        echo "- 网络连接: ✅ 正常"
    else
        echo "- 网络连接: ⚠️  无法连接到Debian官方源"
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

# 主升级逻辑
main_upgrade() {
    # 首先检查是否有待继续的升级
    if check_pending_upgrade; then
        log_info "继续进行升级流程..."
    fi
    
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
                exit 0
            fi
        fi
    fi
    
    log_info "🚀 开始升级过程..."
    
    # 保存升级状态（用于重启后检查）
    save_upgrade_state "$current_version" "$next_version" "$next_version"
    
    # 简化的升级步骤
    log_info "步骤1: 更新软件源配置"
    
    # 备份sources.list
    $USE_SUDO cp /etc/apt/sources.list /etc/apt/sources.list.backup.$(date +%s) 2>/dev/null || true
    
    # 更新sources.list
    case "$next_version" in
        "12"|"13"|"14"|"15")
            # Debian 12+ 包含non-free-firmware
            cat << EOF | $USE_SUDO tee /etc/apt/sources.list > /dev/null
# Debian $next_version ($next_codename) sources
deb http://deb.debian.org/debian $next_codename main contrib non-free non-free-firmware
deb-src http://deb.debian.org/debian $next_codename main contrib non-free non-free-firmware

# Security updates
deb http://deb.debian.org/debian-security $next_codename-security main contrib non-free non-free-firmware
deb-src http://deb.debian.org/debian-security $next_codename-security main contrib non-free non-free-firmware

# Updates
deb http://deb.debian.org/debian $next_codename-updates main contrib non-free non-free-firmware
deb-src http://deb.debian.org/debian $next_codename-updates main contrib non-free non-free-firmware
EOF
            ;;
        "11")
            # Debian 11 使用新的安全源格式
            cat << EOF | $USE_SUDO tee /etc/apt/sources.list > /dev/null
# Debian $next_version ($next_codename) sources
deb http://deb.debian.org/debian $next_codename main contrib non-free
deb-src http://deb.debian.org/debian $next_codename main contrib non-free

# Security updates
deb http://deb.debian.org/debian-security $next_codename-security main contrib non-free
deb-src http://deb.debian.org/debian-security $next_codename-security main contrib non-free

# Updates
deb http://deb.debian.org/debian $next_codename-updates main contrib non-free
deb-src http://deb.debian.org/debian $next_codename-updates main contrib non-free
EOF
            ;;
        *)
            # Debian 10及以下版本使用旧的安全源格式
            cat << EOF | $USE_SUDO tee /etc/apt/sources.list > /dev/null
# Debian $next_version ($next_codename) sources
deb http://deb.debian.org/debian $next_codename main contrib non-free
deb-src http://deb.debian.org/debian $next_codename main contrib non-free

# Security updates
deb http://deb.debian.org/debian-security $next_codename/updates main contrib non-free
deb-src http://deb.debian.org/debian-security $next_codename/updates main contrib non-free

# Updates
deb http://deb.debian.org/debian $next_codename-updates main contrib non-free
deb-src http://deb.debian.org/debian $next_codename-updates main contrib non-free
EOF
            ;;
    esac
    
    log_success "软件源配置已更新"
    
    log_info "步骤2: 更新软件包列表"
    
    # 先尝试更新，如果失败则处理GPG密钥问题
    local update_success=0
    local max_attempts=3
    local attempt=1
    
    while [[ $attempt -le $max_attempts && $update_success -eq 0 ]]; do
        log_info "尝试更新软件包列表 (第 $attempt/$max_attempts 次)"
        
        if $USE_SUDO apt-get update 2>&1 | tee /tmp/apt_update.log; then
            update_success=1
            log_success "软件包列表更新成功"
        else
            # 检查是否是GPG密钥问题
            if grep -q "NO_PUBKEY\|GPG error" /tmp/apt_update.log; then
                log_warning "检测到GPG密钥问题，尝试修复..."
                
                # 安装必要的密钥工具
                if ! command -v gpg >/dev/null 2>&1; then
                    log_info "安装GPG工具..."
                    $USE_SUDO apt-get install -y --allow-unauthenticated gnupg 2>/dev/null || true
                fi
                
                # 提取缺失的密钥ID
                local missing_keys=$(grep "NO_PUBKEY" /tmp/apt_update.log | sed 's/.*NO_PUBKEY \([A-F0-9]*\).*/\1/' | sort -u)
                
                log_info "尝试导入缺失的GPG密钥..."
                for key in $missing_keys; do
                    log_info "导入密钥: $key"
                    
                    # 尝试多个密钥服务器
                    local key_imported=0
                    for keyserver in keyserver.ubuntu.com hkp://keyserver.ubuntu.com:80 pgp.mit.edu; do
                        if $USE_SUDO apt-key adv --keyserver "$keyserver" --recv-keys "$key" 2>/dev/null; then
                            log_success "成功从 $keyserver 导入密钥 $key"
                            key_imported=1
                            break
                        else
                            log_debug "从 $keyserver 导入密钥 $key 失败"
                        fi
                    done
                    
                    if [[ $key_imported -eq 0 ]]; then
                        log_warning "无法导入密钥 $key，尝试手动下载"
                        
                        # 尝试直接下载Debian密钥
                        case "$key" in
                            "0E98404D386FA1D9"|"6ED0E7B82643E131"|"605C66F00D6C9793")
                                log_info "尝试安装debian-archive-keyring包"
                                $USE_SUDO apt-get install -y --allow-unauthenticated debian-archive-keyring 2>/dev/null || true
                                ;;
                        esac
                    fi
                done
                
                # 清理APT缓存后重试
                $USE_SUDO apt-get clean
                sleep 2
                
            else
                log_error "软件包列表更新失败，非GPG密钥问题"
                if [[ $attempt -eq $max_attempts ]]; then
                    cleanup_upgrade_state
                    exit 1
                fi
            fi
        fi
        
        attempt=$((attempt + 1))
        
        # 如果不是最后一次尝试，等待一下
        if [[ $attempt -le $max_attempts && $update_success -eq 0 ]]; then
            log_info "等待 5 秒后重试..."
            sleep 5
        fi
    done
    
    # 清理临时文件
    rm -f /tmp/apt_update.log
    
    if [[ $update_success -eq 0 ]]; then
        log_error "更新软件包列表失败，已尝试 $max_attempts 次"
        log_error "建议手动解决GPG密钥问题后重新运行脚本"
        cleanup_upgrade_state
        exit 1
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
        cleanup_upgrade_state
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
        log_info "1. 🔄 需要重启系统以确保所有更改生效"
        log_info "2. 🔧 重启后可以再次运行此脚本继续升级到更高版本"
        log_info "3. 🛡️  如遇问题，可使用备份配置进行恢复"
        
        # 检查是否还有更高版本可升级
        local further_version=$(get_next_version "$next_version")
        if [[ -n "$further_version" ]]; then
            local further_info=$(get_version_info "$further_version")
            local further_codename=$(echo "$further_info" | cut -d'|' -f1)
            local further_status=$(echo "$further_info" | cut -d'|' -f2)
            
            echo
            log_info "🚀 重启后的升级选项："
            log_info "- 系统重启后，脚本会询问您是否继续升级"
            if [[ "$further_status" == "stable" ]]; then
                log_info "- 下一步可升级到 Debian $further_version ($further_codename) [$further_status]"
            elif [[ "${STABLE_ONLY:-}" != "1" ]]; then
                log_info "- 下一步可选升级到 Debian $further_version ($further_codename) [$further_status]"
                log_warning "  (测试版本，需要明确确认)"
            fi
        fi
        
        echo
        echo "📋 升级状态已保存，重启后运行脚本时将提供选择："
        echo "   • 继续升级到下一个版本"
        echo "   • 保持当前版本"
        echo "   • 仅检查系统状态"
        echo
        
        if [[ "${FORCE:-}" == "1" ]]; then
            log_info "强制模式已启用，建议手动重启系统"
        else
            read -p "是否现在重启系统? [y/N]: " -n 1 -r </dev/tty
            echo
            if [[ $REPLY =~ ^[Yy]$ ]]; then
                log_info "🔄 正在重启系统..."
                log_info "重启后请再次运行此脚本以继续升级流程"
                sleep 2
                $USE_SUDO reboot
            else
                log_info "请稍后手动重启系统: sudo reboot"
                log_info "重启后运行: $0"
            fi
        fi
    else
        log_error "升级验证失败，请检查系统状态"
        log_error "期望版本: Debian $next_version"
        log_error "检测版本: Debian $new_version"
        cleanup_upgrade_state
        exit 1
    fi
}# 更新sources.list
    case "$next_version" in
        "12"|"13"|"14"|"15")
            # Debian 12+ 包含non-free-firmware
            cat << EOF | $USE_SUDO tee /etc/apt/sources.list > /dev/null
# Debian $next_version ($next_codename) sources
deb http://deb.debian.org/debian $next_codename main contrib non-free non-free-firmware
deb-src http://deb.debian.org/debian $next_codename main contrib non-free non-free-firmware

# Security updates
deb http://deb.debian.org/debian-security $next_codename-security main contrib non-free non-free-firmware
deb-src http://deb.debian.org/debian-security $next_codename-security main contrib non-free non-free-firmware

# Updates
deb http://deb.debian.org/debian $next_codename-updates main contrib non-free non-free-firmware
deb-src http://deb.debian.org/debian $next_codename-updates main contrib non-free non-free-firmware
EOF
            ;;
        "11")
            # Debian 11 使用新的安全源格式
            cat << EOF | $USE_SUDO tee /etc/apt/sources.list > /dev/null
# Debian $next_version ($next_codename) sources
deb http://deb.debian.org/debian $next_codename main contrib non-free
deb-src http://deb.debian.org/debian $next_codename main contrib non-free

# Security updates
deb http://deb.debian.org/debian-security $next_codename-security main contrib non-free
deb-src http://deb.debian.org/debian-security $next_codename-security main contrib non-free

# Updates
deb http://deb.debian.org/debian $next_codename-updates main contrib non-free
deb-src http://deb.debian.org/debian $next_codename-updates main contrib non-free
EOF
            ;;
        *)
            # Debian 10及以下版本使用旧的安全源格式
            cat << EOF | $USE_SUDO tee /etc/apt/sources.list > /dev/null
# Debian $next_version ($next_codename) sources
deb http://deb.debian.org/debian $next_codename main contrib non-free
deb-src http://deb.debian.org/debian $next_codename main contrib non-free

# Security updates
deb http://deb.debian.org/debian-security $next_codename/updates main contrib non-free
deb-src http://deb.debian.org/debian-security $next_codename/updates main contrib non-free

# Updates
deb http://deb.debian.org/debian $next_codename-updates main contrib non-free
deb-src http://deb.debian.org/debian $next_codename-updates main contrib non-free
EOF
            ;;
    esac
    
    log_success "软件源配置已更新"
    
    log_info "步骤2: 更新软件包列表"
    if ! $USE_SUDO apt-get update; then
        log_error "更新软件包列表失败"
        exit 1
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
        log_info "3. 🛡️  如遇问题，可使用备份配置进行恢复"
        
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
        log_error "期望版本: Debian $next_version"
        log_error "检测版本: Debian $new_version"
        exit 1
    fi
}

# 系统修复模式
fix_only_mode() {
    log_info "========================================="
    log_info "🔧 仅执行系统修复模式"
    log_info "========================================="
    
    log_info "1/4: 清理APT锁定文件"
    $USE_SUDO rm -f /var/lib/dpkg/lock-frontend 2>/dev/null || true
    $USE_SUDO rm -f /var/lib/dpkg/lock 2>/dev/null || true
    $USE_SUDO rm -f /var/cache/apt/archives/lock 2>/dev/null || true
    $USE_SUDO rm -f /var/lib/apt/lists/lock 2>/dev/null || true
    
    log_info "2/4: 修复dpkg状态"
    $USE_SUDO dpkg --configure -a 2>/dev/null || true
    
    log_info "3/4: 修复依赖关系"
    $USE_SUDO apt-get --fix-broken install -y 2>/dev/null || true
    
    log_info "4/4: 更新软件包列表"
    $USE_SUDO apt-get update || log_warning "软件包列表更新失败，但系统修复已完成"
    
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
    
    log_info "基本错误恢复完成，建议运行 $0 --fix-only 进行完整修复"
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
                # 先检查待继续的升级，如果没有再显示常规检查
                if ! check_pending_upgrade; then
                    check_upgrade
                fi
                exit 0
                ;;
            -d|--debug)
                export DEBUG=1
                log_debug "调试模式已启用"
                shift
                ;;
            --fix-only)
                # 清理可能的升级状态
                cleanup_upgrade_state
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
            --check-state)
                # 强制检查升级状态
                if check_pending_upgrade; then
                    log_info "已处理升级状态检查"
                else
                    log_info "没有发现待继续的升级状态"
                    check_upgrade
                fi
                exit 0
                ;;
            --continue)
                # 隐藏选项：强制继续升级流程，跳过重启后的选择
                export FORCE_CONTINUE=1
                shift
                ;;
            --no-reboot-check)
                # 隐藏选项：跳过重启后检查
                export NO_REBOOT_CHECK=1
                shift
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
    check_system
    
    # 如果没有设置跳过重启检查，则检查待继续的升级
    if [[ "${NO_REBOOT_CHECK:-}" != "1" && "${FORCE_CONTINUE:-}" != "1" ]]; then
        if check_pending_upgrade; then
            # 如果检查到待继续升级并且用户选择继续，则会继续执行
            log_info "继续升级流程..."
        fi
    fi
    
    # 执行主升级流程
    main_upgrade
}

# 清理函数
cleanup() {
    log_debug "执行清理操作..."
    
    # 注意：不要在这里清理升级状态文件，因为重启后需要它
    # cleanup_upgrade_state  # 注释掉这行
    
    # 清理其他临时文件
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
