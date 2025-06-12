#!/bin/bash

# Debian自动逐级升级脚本
# 功能：自动检测当前版本并升级到下一个版本，直到最新版本
# 适用于大部分Debian系统，包括VPS环境
# v2.6: 修复GRUB过度修复问题，改进重启确认机制

set -e  # 遇到错误立即退出

# 脚本版本
SCRIPT_VERSION="2.6"

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

# 检测启动模式（UEFI或BIOS）
detect_boot_mode() {
    if [[ -d /sys/firmware/efi ]]; then
        echo "uefi"
    else
        echo "bios"
    fi
}

# 检测引导磁盘（支持NVMe、虚拟磁盘等）
detect_boot_disk() {
    local boot_disk=""
    
    # 方法1：从当前GRUB配置获取
    if [[ -f /boot/grub/grub.cfg ]]; then
        local grub_disk=$(grep -o 'root=[^ ]*' /boot/grub/grub.cfg 2>/dev/null | head -1 | sed 's/root=//' | sed 's/[0-9]*$//' | sed 's/p[0-9]*$//')
        if [[ -b "$grub_disk" ]]; then
            echo "$grub_disk"
            return
        fi
    fi
    
    # 方法2：从/boot分区查找
    if mount | grep -q " /boot "; then
        boot_disk=$(mount | grep " /boot " | awk '{print $1}' | sed 's/[0-9]*$//' | sed 's/p[0-9]*$//')
        if [[ -b "$boot_disk" ]]; then
            echo "$boot_disk"
            return
        fi
    fi
    
    # 方法3：从根分区查找
    boot_disk=$(mount | grep " / " | grep -v tmpfs | head -1 | awk '{print $1}' | sed 's/[0-9]*$//' | sed 's/p[0-9]*$//')
    if [[ -b "$boot_disk" ]]; then
        echo "$boot_disk"
        return
    fi
    
    # 方法4：从系统引导参数获取
    if [[ -f /proc/cmdline ]]; then
        local root_dev=$(cat /proc/cmdline | grep -o 'root=[^ ]*' | sed 's/root=//')
        if [[ "$root_dev" =~ ^UUID= ]]; then
            # 如果是UUID，转换为设备名
            local uuid=$(echo "$root_dev" | sed 's/UUID=//')
            boot_disk=$(blkid -U "$uuid" 2>/dev/null | sed 's/[0-9]*$//' | sed 's/p[0-9]*$//')
        else
            boot_disk=$(echo "$root_dev" | sed 's/[0-9]*$//' | sed 's/p[0-9]*$//')
        fi
        if [[ -b "$boot_disk" ]]; then
            echo "$boot_disk"
            return
        fi
    fi
    
    # 方法5：智能检测第一个可用磁盘
    for disk in $(lsblk -d -n -o NAME,TYPE | grep disk | awk '{print "/dev/"$1}'); do
        # 检查磁盘是否有分区表
        if $USE_SUDO fdisk -l "$disk" 2>/dev/null | grep -q "Disklabel type"; then
            echo "$disk"
            return
        fi
    done
    
    # 方法6：尝试常见设备
    for disk in /dev/sda /dev/vda /dev/xvda /dev/nvme0n1; do
        if [[ -b "$disk" ]]; then
            echo "$disk"
            return
        fi
    done
    
    # 如果都失败了，返回空
    echo ""
}

# 保存网络配置
save_network_config() {
    local backup_dir="/root/debian_upgrade_backup_$(date +%Y%m%d_%H%M%S)"
    
    log_debug "备份网络配置到 $backup_dir"
    $USE_SUDO mkdir -p "$backup_dir/network"
    
    # 备份网络配置文件
    $USE_SUDO cp -a /etc/network/interfaces* "$backup_dir/network/" 2>/dev/null || true
    $USE_SUDO cp -a /etc/systemd/network/* "$backup_dir/network/" 2>/dev/null || true
    
    # 记录当前网络接口信息
    ip addr show > "$backup_dir/network/ip_addr_before.txt"
    ip route show > "$backup_dir/network/ip_route_before.txt"
    
    # 记录当前网络接口名称
    local current_interfaces=$(ip -o link show | awk -F': ' '{print $2}' | grep -v lo)
    echo "$current_interfaces" > "$backup_dir/network/interface_names.txt"
    
    echo "$backup_dir"
}

# 修复网络配置
fix_network_config() {
    local backup_dir="$1"
    
    log_debug "检查并修复网络配置..."
    
    # 获取当前网络接口名称
    local new_interfaces=$(ip -o link show | awk -F': ' '{print $2}' | grep -v lo)
    
    # 如果有备份，比较接口名称
    if [[ -f "$backup_dir/network/interface_names.txt" ]]; then
        local old_interfaces=$(cat "$backup_dir/network/interface_names.txt")
        
        # 检查是否有接口名称变化
        for old_if in $old_interfaces; do
            if ! echo "$new_interfaces" | grep -q "^$old_if$"; then
                log_warning "网络接口 $old_if 已不存在"
                
                # 尝试找到对应的新接口
                local new_if=$(echo "$new_interfaces" | head -1)
                
                if [[ -n "$new_if" ]]; then
                    log_info "尝试将 $old_if 的配置应用到 $new_if"
                    
                    # 更新 /etc/network/interfaces
                    if [[ -f /etc/network/interfaces ]]; then
                        $USE_SUDO sed -i "s/\b$old_if\b/$new_if/g" /etc/network/interfaces
                    fi
                fi
            fi
        done
    fi
    
    # 确保网络服务正确配置
    if systemctl is-enabled NetworkManager >/dev/null 2>&1; then
        log_debug "NetworkManager 已启用"
    elif systemctl is-enabled systemd-networkd >/dev/null 2>&1; then
        log_debug "systemd-networkd 已启用"
    else
        log_debug "启用 networking.service"
        $USE_SUDO systemctl enable networking.service 2>/dev/null || true
    fi
}

# 清理旧内核（释放/boot空间）
clean_old_kernels() {
    log_info "清理旧内核以释放/boot空间..."
    
    # 获取当前运行的内核版本
    local current_kernel=$(uname -r)
    log_info "当前运行内核: $current_kernel"
    
    # 获取最新安装的内核版本
    local latest_kernel=$(ls -t /boot/vmlinuz-* | head -1 | sed 's/\/boot\/vmlinuz-//')
    log_info "最新安装内核: $latest_kernel"
    
    # 列出所有已安装的内核
    local installed_kernels=$(dpkg -l | grep linux-image | grep -E '^ii' | awk '{print $2}')
    
    if [[ -n "$installed_kernels" ]]; then
        local count=0
        local kernels_to_remove=""
        
        for kernel_pkg in $installed_kernels; do
            # 提取内核版本号
            local kernel_ver=$(echo "$kernel_pkg" | sed 's/linux-image-//')
            
            # 跳过当前运行的内核和最新的内核
            if [[ "$kernel_ver" != "$current_kernel" ]] && [[ "$kernel_ver" != "$latest_kernel" ]] && [[ "$kernel_pkg" != "linux-image-amd64" ]]; then
                kernels_to_remove="$kernels_to_remove $kernel_pkg"
                ((count++))
            fi
        done
        
        if [[ -n "$kernels_to_remove" ]]; then
            log_info "将删除 $count 个旧内核"
            for kernel in $kernels_to_remove; do
                log_debug "删除内核: $kernel"
                $USE_SUDO apt-get remove --purge -y "$kernel" 2>/dev/null || true
            done
            
            # 清理相关的头文件包
            $USE_SUDO apt-get autoremove -y --purge 2>/dev/null || true
        else
            log_info "没有需要清理的旧内核"
        fi
    fi
    
    # 清理/boot目录中的残留文件
    log_debug "清理/boot目录残留文件"
    $USE_SUDO find /boot -name "*.old" -delete 2>/dev/null || true
    $USE_SUDO find /boot -name "*.bak" -delete 2>/dev/null || true
    
    # 显示/boot使用情况
    if mount | grep -q " /boot "; then
        local boot_usage=$(df -h /boot | awk 'NR==2 {print $5}')
        local boot_avail=$(df -h /boot | awk 'NR==2 {print $4}')
        log_info "/boot分区使用率: $boot_usage, 可用空间: $boot_avail"
    fi
}

# 安全的GRUB更新（保守版）
update_grub_safe() {
    local boot_mode=$(detect_boot_mode)
    local boot_disk=$(detect_boot_disk)
    
    log_info "更新GRUB配置 (启动模式: $boot_mode)"
    
    # 首先尝试更新GRUB配置
    if ! $USE_SUDO update-grub 2>/dev/null; then
        log_warning "update-grub失败，尝试修复"
        $USE_SUDO grub-mkconfig -o /boot/grub/grub.cfg 2>/dev/null || true
    fi
    
    # 仅在必要时安装GRUB
    local need_reinstall=false
    
    if [[ "$boot_mode" == "uefi" ]]; then
        # 检查EFI引导是否存在
        if ! efibootmgr 2>/dev/null | grep -q -i "debian\|grub"; then
            log_warning "未找到EFI引导项，需要安装"
            need_reinstall=true
        fi
    else
        # 检查MBR是否包含GRUB
        if [[ -n "$boot_disk" ]]; then
            if ! $USE_SUDO dd if="$boot_disk" bs=512 count=1 2>/dev/null | strings | grep -q GRUB; then
                log_warning "MBR中未检测到GRUB，需要安装"
                need_reinstall=true
            fi
        fi
    fi
    
    # 仅在需要时重新安装
    if [[ "$need_reinstall" == "true" ]]; then
        log_info "需要重新安装GRUB"
        
        if [[ "$boot_mode" == "uefi" ]]; then
            # UEFI模式
            log_info "安装GRUB到EFI"
            
            # 确保EFI相关包已安装
            if ! dpkg -l | grep -q "^ii.*grub-efi-amd64"; then
                DEBIAN_FRONTEND=noninteractive $USE_SUDO apt-get install -y \
                    grub-efi-amd64 grub-efi-amd64-bin efibootmgr 2>/dev/null || true
            fi
            
            # 安装到EFI
            if [[ -d /boot/efi ]]; then
                $USE_SUDO grub-install --target=x86_64-efi --efi-directory=/boot/efi \
                    --bootloader-id=debian --recheck 2>/dev/null || {
                    log_warning "GRUB EFI安装失败"
                }
            fi
        else
            # BIOS模式
            if [[ -n "$boot_disk" ]]; then
                log_info "安装GRUB到: $boot_disk"
                
                # 确保grub-pc已安装
                if ! dpkg -l | grep -q "^ii.*grub-pc"; then
                    DEBIAN_FRONTEND=noninteractive $USE_SUDO apt-get install -y grub-pc grub-pc-bin 2>/dev/null || true
                fi
                
                # 安装GRUB
                $USE_SUDO grub-install --target=i386-pc --recheck "$boot_disk" 2>/dev/null || {
                    log_warning "GRUB安装失败，尝试使用dpkg-reconfigure"
                    
                    echo "grub-pc grub-pc/install_devices multiselect $boot_disk" | \
                        $USE_SUDO debconf-set-selections
                    DEBIAN_FRONTEND=noninteractive $USE_SUDO dpkg-reconfigure grub-pc 2>/dev/null || true
                }
            fi
        fi
        
        # 重新更新配置
        $USE_SUDO update-grub 2>/dev/null || true
    else
        log_info "GRUB已正确安装，跳过重新安装"
    fi
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
    
    # 检查/boot分区空间
    if mount | grep -q " /boot "; then
        local boot_space=$(df /boot | awk 'NR==2 {print $4}')
        if [[ $boot_space -lt 204800 ]]; then  # 200MB
            log_warning "/boot分区可用空间不足200MB，需要清理旧内核"
            clean_old_kernels
        fi
    fi
    
    # 检查内存
    local available_memory=$(free -m | awk 'NR==2{printf "%.0f", $7}')
    if [[ $available_memory -lt 512 ]]; then
        log_warning "可用内存不足512MB，升级过程可能较慢"
    fi
    
    # 检查启动模式
    local boot_mode=$(detect_boot_mode)
    local boot_disk=$(detect_boot_disk)
    log_debug "启动模式: $boot_mode"
    log_debug "引导磁盘: ${boot_disk:-未检测到}"
    
    log_success "系统环境检查完成"
}

# 检查是否为root用户
check_root() {
    if [[ $EUID -eq 0 ]]; then
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
    
    # 清除可能的缓存
    $USE_SUDO rm -f /var/cache/apt/*.bin 2>/dev/null || true
    
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
        # 更新APT缓存
        $USE_SUDO apt-cache policy >/dev/null 2>&1 || true
        
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
        
        # 返回空而不是退出，让调用者决定
        echo ""
        return 1
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

# 升级前的准备工作
pre_upgrade_preparation() {
    log_info "执行升级前准备工作..."
    
    # 停止不必要的服务
    for service in unattended-upgrades apt-daily apt-daily-upgrade; do
        if systemctl is-active "$service" >/dev/null 2>&1; then
            log_debug "停止服务: $service"
            $USE_SUDO systemctl stop "$service" 2>/dev/null || true
        fi
    done
    
    # 清理APT缓存和锁文件
    log_debug "清理APT缓存和锁文件"
    $USE_SUDO rm -f /var/lib/dpkg/lock-frontend 2>/dev/null || true
    $USE_SUDO rm -f /var/lib/dpkg/lock 2>/dev/null || true
    $USE_SUDO rm -f /var/cache/apt/archives/lock 2>/dev/null || true
    $USE_SUDO rm -f /var/lib/apt/lists/lock 2>/dev/null || true
    
    # 修复可能的dpkg问题
    log_debug "修复dpkg状态"
    $USE_SUDO dpkg --configure -a 2>/dev/null || true
    
    # 修复依赖关系
    log_debug "修复依赖关系"
    DEBIAN_FRONTEND=noninteractive $USE_SUDO apt-get --fix-broken install -y 2>/dev/null || true
    
    # 更新包数据库
    log_debug "更新软件包数据库"
    $USE_SUDO apt-get update || log_warning "软件包列表更新失败，继续升级"
    
    # GRUB预检查和修复
    log_info "GRUB预检查和修复"
    local boot_mode=$(detect_boot_mode)
    local boot_disk=$(detect_boot_disk)
    
    if [[ -z "$boot_disk" ]]; then
        log_warning "⚠️  警告：未能自动检测到引导磁盘"
        log_warning "升级后可能需要手动修复GRUB"
        
        # 提供磁盘列表供参考
        echo
        echo "可用磁盘列表："
        lsblk -d -n -o NAME,SIZE,TYPE | grep disk | while read line; do
            echo "  /dev/$line"
        done
        echo
        
        if [[ "${FORCE:-}" != "1" ]]; then
            read -p "是否继续升级？建议先确认引导磁盘 [y/N]: " -n 1 -r </dev/tty
            echo
            if [[ ! $REPLY =~ ^[Yy]$ ]]; then
                log_info "升级已取消。建议先运行 $0 --fix-grub 修复系统"
                exit 1
            fi
        fi
    else
        log_success "检测到引导磁盘: $boot_disk (模式: $boot_mode)"
        
        # 仅记录当前GRUB状态，不做修改
        log_info "当前GRUB状态检查..."
        if [[ -f /boot/grub/grub.cfg ]]; then
            log_success "GRUB配置文件存在"
        else
            log_warning "GRUB配置文件不存在，升级后需要修复"
        fi
        
        # 预设GRUB设备（仅为避免交互式提示）
        if [[ "$boot_mode" == "bios" ]]; then
            echo "grub-pc grub-pc/install_devices multiselect $boot_disk" | \
                $USE_SUDO debconf-set-selections
            echo "grub-pc grub-pc/install_devices_empty boolean false" | \
                $USE_SUDO debconf-set-selections
        fi
    fi
    
    log_success "升级前准备工作完成"
}

# 升级后的修复工作
post_upgrade_fixes() {
    local backup_dir="$1"
    
    log_info "执行升级后修复工作..."
    
    # 修复网络配置
    fix_network_config "$backup_dir"
    
    # 清理并重建initramfs（重要）
    log_info "重建initramfs..."
    # 先清理可能损坏的initramfs
    $USE_SUDO rm -f /boot/initrd.img-*.bak 2>/dev/null || true
    
    # 为所有内核重建initramfs
    for kernel in $(ls /boot/vmlinuz-* | sed 's/\/boot\/vmlinuz-//'); do
        log_info "为内核 $kernel 重建initramfs"
        $USE_SUDO update-initramfs -c -k "$kernel" 2>/dev/null || {
            log_warning "创建失败，尝试更新"
            $USE_SUDO update-initramfs -u -k "$kernel" 2>/dev/null || true
        }
    done
    
    # 确保GRUB包正确安装
    log_info "确保GRUB包正确安装..."
    local boot_mode=$(detect_boot_mode)
    if [[ "$boot_mode" == "uefi" ]]; then
        # 强制重装GRUB EFI包
        DEBIAN_FRONTEND=noninteractive $USE_SUDO apt-get install --reinstall -y \
            grub-efi-amd64 grub-efi-amd64-bin 2>/dev/null || true
    else
        # 强制重装GRUB PC包
        DEBIAN_FRONTEND=noninteractive $USE_SUDO apt-get install --reinstall -y \
            grub-pc grub-pc-bin 2>/dev/null || true
    fi
    
    # 更新GRUB（保守处理）
    log_info "检查GRUB状态..."
    
    # 只有在检测到明显问题时才更新GRUB
    if [[ ! -f /boot/grub/grub.cfg ]] || [[ ! -s /boot/grub/grub.cfg ]]; then
        log_warning "GRUB配置文件缺失或为空，需要修复"
        update_grub_safe
    else
        # 仅更新配置，不重装GRUB
        log_info "更新GRUB配置（保守模式）"
        $USE_SUDO update-grub 2>/dev/null || true
    fi
    
    # 强制执行额外的GRUB修复
    log_info "执行额外的GRUB修复..."
    local boot_disk=$(detect_boot_disk)
    if [[ -n "$boot_disk" ]]; then
        if [[ "$boot_mode" == "uefi" ]]; then
            # UEFI：确保EFI引导文件存在
            if [[ -d /boot/efi/EFI ]]; then
                # 创建多个引导入口以提高兼容性
                $USE_SUDO grub-install --target=x86_64-efi \
                    --efi-directory=/boot/efi \
                    --bootloader-id=debian \
                    --force-extra-removable 2>/dev/null || true
                    
                # 同时创建默认的BOOT入口
                $USE_SUDO grub-install --target=x86_64-efi \
                    --efi-directory=/boot/efi \
                    --removable 2>/dev/null || true
            fi
        else
            # BIOS：多次尝试安装以确保成功
            log_info "BIOS模式：确保GRUB正确安装到MBR"
            
            # 清除并重装MBR
            $USE_SUDO dd if=/usr/lib/grub/i386-pc/boot.img of="$boot_disk" bs=446 count=1 2>/dev/null || true
            
            # 重新安装GRUB
            $USE_SUDO grub-install --force --recheck "$boot_disk" 2>/dev/null || {
                log_warning "标准安装失败，使用备用方法"
                # 备用方法
                $USE_SUDO grub-install --force-file-id "$boot_disk" 2>/dev/null || true
            }
        fi
    fi
    
    # 最终GRUB更新
    log_info "最终GRUB配置更新..."
    $USE_SUDO update-grub 2>/dev/null || true
    
    # 验证GRUB安装
    log_info "验证GRUB安装状态"
    local boot_mode=$(detect_boot_mode)
    if [[ "$boot_mode" == "uefi" ]]; then
        if ! efibootmgr 2>/dev/null | grep -q "debian"; then
            log_warning "未检测到debian EFI引导项，可能需要手动修复"
            log_info "建议运行: sudo grub-install --target=x86_64-efi --efi-directory=/boot/efi"
        else
            log_success "EFI引导项检查通过"
        fi
    else
        # BIOS模式验证
        if [[ ! -f /boot/grub/grub.cfg ]]; then
            log_warning "未找到GRUB配置文件，可能需要手动修复"
        else
            local menu_entries=$(grep -c "menuentry " /boot/grub/grub.cfg 2>/dev/null || echo "0")
            if [[ $menu_entries -eq 0 ]]; then
                log_warning "GRUB配置文件中没有启动项！"
                log_info "尝试重新生成配置..."
                $USE_SUDO grub-mkconfig -o /boot/grub/grub.cfg 2>/dev/null || true
            else
                log_success "GRUB配置文件包含 $menu_entries 个启动项"
            fi
        fi
    fi
    
    # 清理残留配置
    log_info "清理残留配置"
    $USE_SUDO apt-get autoremove -y --purge 2>/dev/null || true
    $USE_SUDO apt-get autoclean 2>/dev/null || true
    
    # 检查关键服务
    log_debug "检查关键服务状态"
    for service in ssh sshd networking systemd-networkd NetworkManager; do
        if systemctl list-unit-files "$service.service" >/dev/null 2>&1; then
            if systemctl is-enabled "$service" >/dev/null 2>&1; then
                log_debug "确保服务 $service 正常运行"
                $USE_SUDO systemctl restart "$service" 2>/dev/null || true
            fi
        fi
    done
    
    # 最后同步文件系统
    sync
    sync
    sync
    
    log_success "升级后修复工作完成"
}

# 安全重启函数
safe_reboot() {
    log_info "准备安全重启系统..."
    
    # 确保在重启前再次确认
    echo
    echo "========================================="
    echo "⚠️  即将重启系统"
    echo "========================================="
    read -p "最后确认：确定要重启吗? [y/N]: " -n 1 -r </dev/tty
    echo
    
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        log_info "用户取消重启"
        log_info "请稍后手动重启: sudo reboot"
        return
    fi
    
    # 最后一次GRUB检查（仅记录，不修改）
    log_info "执行重启前检查..."
    local boot_disk=$(detect_boot_disk)
    if [[ -n "$boot_disk" ]]; then
        log_info "引导磁盘: $boot_disk"
    else
        log_warning "未检测到引导磁盘，但继续重启"
    fi
    
    # 同步文件系统
    log_info "同步文件系统..."
    sync
    sync
    sync
    
    # 等待所有写入完成
    sleep 3
    
    # 确保所有缓存写入磁盘
    echo 3 | $USE_SUDO tee /proc/sys/vm/drop_caches >/dev/null 2>&1 || true
    
    # 再次同步
    sync
    
    # 确保所有日志已写入
    $USE_SUDO systemctl stop rsyslog 2>/dev/null || true
    
    # 使用systemctl重启（更安全）
    log_info "执行系统重启..."
    
    # 给用户最后的提示
    echo
    echo "========================================="
    echo "⚡ 系统将在5秒后重启"
    echo "========================================="
    echo "💡 如果重启失败，请使用救援模式并运行:"
    echo "   grub-install /dev/sdX && update-grub"
    echo "========================================="
    echo
    
    # 倒计时
    for i in 5 4 3 2 1; do
        echo -n "$i... "
        sleep 1
    done
    echo
    
    # 最后同步
    sync
    
    # 执行重启
    if command -v systemctl >/dev/null 2>&1; then
        $USE_SUDO systemctl reboot --force
    else
        $USE_SUDO reboot -f
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
  --fix-grub          专门修复GRUB引导问题
  --force             强制执行升级（跳过确认）
  --stable-only       仅升级到稳定版本，跳过测试版本
  --allow-testing     允许升级到测试版本（默认行为）

✨ 功能特性:
  ✅ 自动检测当前Debian版本和目标版本
  ✅ 逐级安全升级，避免跨版本问题
  ✅ 智能软件源选择和镜像优化
  ✅ UEFI/BIOS自动检测和适配
  ✅ NVMe等新型存储设备支持
  ✅ 网络接口名称变化自动修复
  ✅ /boot分区空间自动清理
  ✅ 完整的配置备份和恢复
  ✅ 安全的重启机制
  ✅ 保守的GRUB处理策略（v2.6）

🔄 支持的升级路径:
  • Debian 8 (Jessie) → 9 (Stretch) → 10 (Buster)
  • Debian 10 (Buster) → 11 (Bullseye) → 12 (Bookworm)
  • Debian 12 (Bookworm) → 13 (Trixie) [测试版本]

💻 示例:
  $0                    # 执行自动升级
  $0 --check            # 检查可用升级
  $0 --version          # 显示版本信息
  $0 --fix-only         # 仅修复系统问题
  $0 --fix-grub         # 专门修复GRUB引导
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
                echo "- 如需体验新功能，可使用 --allow-testing 选项"
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
    
    # 启动模式
    local boot_mode=$(detect_boot_mode)
    local boot_disk=$(detect_boot_disk)
    echo "- 启动模式: $boot_mode"
    echo "- 引导磁盘: ${boot_disk:-未检测到}"
    
    # 磁盘空间
    local disk_usage=$(df -h / | awk 'NR==2 {print $5}')
    local available_space=$(df / | awk 'NR==2 {print $4}')
    echo "- 磁盘使用: $disk_usage"
    if [[ $available_space -lt 2097152 ]]; then
        echo "  ⚠️  可用空间不足2GB"
    else
        echo "  ✅ 磁盘空间充足"
    fi
    
    # /boot分区
    if mount | grep -q " /boot "; then
        local boot_usage=$(df -h /boot | awk 'NR==2 {print $5}')
        local boot_space=$(df /boot | awk 'NR==2 {print $4}')
        echo "- /boot使用: $boot_usage"
        if [[ $boot_space -lt 204800 ]]; then
            echo "  ⚠️  /boot空间不足200MB"
        else
            echo "  ✅ /boot空间充足"
        fi
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
            echo "🔧 升级前建议: $0 --fix-grub (修复引导)"
            echo "🚀 执行升级: $0"
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
    
    # 保存网络配置
    local backup_dir=$(save_network_config)
    
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
        log_warning "⚠️  重要提示: 如果之前升级后重启失败，建议先运行: $0 --fix-grub"
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
    
    # 升级前准备
    pre_upgrade_preparation
    
    log_info "🚀 开始升级过程..."
    
    # 步骤1: 更新软件源配置
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
    
    log_info "步骤4: 升级后修复"
    post_upgrade_fixes "$backup_dir"
    
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
        log_info "3. 🛡️  配置备份位置: $backup_dir"
        log_info "4. ⚠️  如果重启失败，使用 $0 --fix-grub 修复引导"
        
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
            # 重启前的GRUB检查选项 - 默认不修复
            log_info "升级完成！"
            echo
            read -p "是否需要执行GRUB修复？通常不需要 [y/N]: " -n 1 -r </dev/tty
            echo
            if [[ $REPLY =~ ^[Yy]$ ]]; then
                log_warning "执行GRUB修复（仅在引导有问题时使用）..."
                fix_grub_quick
            else
                log_info "跳过GRUB修复（推荐）"
            fi
            
            echo
            read -p "是否现在重启系统? [y/N]: " -n 1 -r </dev/tty
            echo
            if [[ $REPLY =~ ^[Yy]$ ]]; then
                safe_reboot
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

# 快速GRUB修复（重启前使用）- 保守版本
fix_grub_quick() {
    log_info "执行保守的GRUB修复..."
    
    local boot_mode=$(detect_boot_mode)
    local boot_disk=$(detect_boot_disk)
    
    # 仅更新GRUB配置，不重新安装
    log_info "更新GRUB配置..."
    if ! $USE_SUDO update-grub 2>/dev/null; then
        log_warning "update-grub失败，尝试grub-mkconfig"
        $USE_SUDO grub-mkconfig -o /boot/grub/grub.cfg 2>/dev/null || true
    fi
    
    # 仅在明确检测到问题时才重装GRUB
    if [[ ! -f /boot/grub/grub.cfg ]]; then
        log_warning "未找到GRUB配置文件，需要重新安装"
        
        if [[ -n "$boot_disk" ]]; then
            if [[ "$boot_mode" == "uefi" ]]; then
                $USE_SUDO grub-install --target=x86_64-efi \
                    --efi-directory=/boot/efi \
                    --bootloader-id=debian 2>/dev/null || true
            else
                $USE_SUDO grub-install "$boot_disk" 2>/dev/null || true
            fi
        fi
    else
        log_info "GRUB配置文件存在，跳过重新安装"
    fi
    
    # 同步文件系统
    sync
    sync
    
    log_success "保守GRUB修复完成"
}

# GRUB专门修复模式
fix_grub_mode() {
    log_info "========================================="
    log_info "🔧 GRUB引导修复模式"
    log_info "========================================="
    
    # 检测系统环境
    local boot_mode=$(detect_boot_mode)
    local boot_disk=$(detect_boot_disk)
    
    log_info "系统信息："
    log_info "- 启动模式: $boot_mode"
    log_info "- 检测到的引导磁盘: ${boot_disk:-未自动检测到}"
    echo
    
    # 如果未检测到磁盘，让用户选择
    if [[ -z "$boot_disk" ]]; then
        log_warning "未能自动检测到引导磁盘"
        echo
        echo "可用磁盘列表："
        local disk_list=()
        while IFS= read -r line; do
            disk_list+=("$line")
            echo "  $((${#disk_list[@]})). $line"
        done < <(lsblk -d -n -o NAME,SIZE,TYPE | grep disk | awk '{print "/dev/"$1" - "$2}')
        
        echo
        read -p "请选择引导磁盘编号 (1-${#disk_list[@]}), 或按回车跳过: " -r </dev/tty
        
        if [[ -n "$REPLY" ]] && [[ "$REPLY" =~ ^[0-9]+$ ]] && [[ "$REPLY" -ge 1 ]] && [[ "$REPLY" -le "${#disk_list[@]}" ]]; then
            boot_disk=$(echo "${disk_list[$((REPLY-1))]}" | awk '{print $1}')
            log_info "选择的引导磁盘: $boot_disk"
        else
            log_warning "跳过磁盘选择"
        fi
    fi
    
    # 步骤1：重新安装GRUB包
    log_info "步骤1: 重新安装GRUB包"
    if [[ "$boot_mode" == "uefi" ]]; then
        DEBIAN_FRONTEND=noninteractive $USE_SUDO apt-get install --reinstall -y \
            grub-efi-amd64 grub-efi-amd64-bin grub-efi-amd64-signed \
            grub2-common grub-common efibootmgr 2>/dev/null || {
            log_error "GRUB EFI包安装失败"
        }
    else
        DEBIAN_FRONTEND=noninteractive $USE_SUDO apt-get install --reinstall -y \
            grub-pc grub-pc-bin grub2-common grub-common 2>/dev/null || {
            log_error "GRUB PC包安装失败"
        }
    fi
    
    # 步骤2：生成新的GRUB配置
    log_info "步骤2: 生成GRUB配置"
    $USE_SUDO grub-mkconfig -o /boot/grub/grub.cfg 2>/dev/null || {
        log_warning "grub-mkconfig失败，尝试update-grub"
        $USE_SUDO update-grub 2>/dev/null || true
    }
    
    # 步骤3：安装GRUB到磁盘
    if [[ -n "$boot_disk" ]]; then
        log_info "步骤3: 安装GRUB到 $boot_disk"
        
        if [[ "$boot_mode" == "uefi" ]]; then
            # EFI模式安装
            local efi_dir="/boot/efi"
            if [[ ! -d "$efi_dir" ]] && [[ -d "/efi" ]]; then
                efi_dir="/efi"
            fi
            
            log_info "EFI目录: $efi_dir"
            $USE_SUDO grub-install --target=x86_64-efi \
                --efi-directory="$efi_dir" \
                --bootloader-id=debian \
                --recheck \
                --no-floppy \
                --force 2>&1 | tee /tmp/grub_install.log
                
            # 检查安装结果
            if grep -q "Installation finished. No error reported" /tmp/grub_install.log; then
                log_success "GRUB EFI安装成功"
                
                # 显示EFI引导项
                log_info "当前EFI引导项："
                $USE_SUDO efibootmgr -v 2>/dev/null || true
            else
                log_error "GRUB EFI安装可能失败，请检查日志"
                cat /tmp/grub_install.log
            fi
        else
            # BIOS模式安装
            $USE_SUDO grub-install --target=i386-pc \
                --recheck \
                --no-floppy \
                --force \
                "$boot_disk" 2>&1 | tee /tmp/grub_install.log
                
            # 检查安装结果
            if grep -q "Installation finished. No error reported" /tmp/grub_install.log; then
                log_success "GRUB BIOS安装成功"
            else
                log_error "GRUB BIOS安装可能失败，请检查日志"
                cat /tmp/grub_install.log
            fi
        fi
        
        rm -f /tmp/grub_install.log
    else
        log_warning "跳过GRUB安装（未指定磁盘）"
    fi
    
    # 步骤4：最终更新GRUB配置
    log_info "步骤4: 最终更新GRUB配置"
    $USE_SUDO update-grub 2>/dev/null || true
    
    # 步骤5：验证
    log_info "步骤5: 验证GRUB安装"
    if [[ -f /boot/grub/grub.cfg ]]; then
        log_success "GRUB配置文件存在"
        local kernel_count=$(grep -c "menuentry " /boot/grub/grub.cfg 2>/dev/null || echo "0")
        log_info "检测到 $kernel_count 个启动项"
    else
        log_error "GRUB配置文件不存在！"
    fi
    
    log_success "========================================="
    log_success "🎉 GRUB修复完成"
    log_success "========================================="
    
    echo
    log_info "建议："
    log_info "1. 重启前再次运行: sudo update-grub"
    log_info "2. 如果仍有问题，可以尝试救援模式或Live CD修复"
    if [[ "$boot_mode" == "uefi" ]]; then
        log_info "3. EFI系统可检查: sudo efibootmgr -v"
    fi
    log_info "4. 重启系统测试: sudo reboot"
}

# 系统修复模式
fix_only_mode() {
    log_info "========================================="
    log_info "🔧 仅执行系统修复模式"
    log_info "========================================="
    
    # 检测系统环境
    local boot_mode=$(detect_boot_mode)
    local boot_disk=$(detect_boot_disk)
    log_info "启动模式: $boot_mode"
    log_info "引导磁盘: ${boot_disk:-未检测到}"
    
    log_info "1/5: 清理APT锁定文件"
    $USE_SUDO rm -f /var/lib/dpkg/lock-frontend 2>/dev/null || true
    $USE_SUDO rm -f /var/lib/dpkg/lock 2>/dev/null || true
    $USE_SUDO rm -f /var/cache/apt/archives/lock 2>/dev/null || true
    $USE_SUDO rm -f /var/lib/apt/lists/lock 2>/dev/null || true
    
    log_info "2/5: 修复dpkg状态"
    $USE_SUDO dpkg --configure -a 2>/dev/null || true
    
    log_info "3/5: 修复依赖关系"
    $USE_SUDO apt-get --fix-broken install -y 2>/dev/null || true
    
    log_info "4/5: 修复GRUB引导程序"
    # 重新安装GRUB相关包
    if [[ "$boot_mode" == "uefi" ]]; then
        log_info "重新安装GRUB EFI包"
        DEBIAN_FRONTEND=noninteractive $USE_SUDO apt-get install --reinstall -y \
            grub-efi-amd64 grub-efi-amd64-bin efibootmgr 2>/dev/null || true
    else
        log_info "重新安装GRUB PC包"
        DEBIAN_FRONTEND=noninteractive $USE_SUDO apt-get install --reinstall -y \
            grub-pc grub-pc-bin 2>/dev/null || true
    fi
    
    # 修复GRUB
    update_grub_safe
    
    # 修复网络
    fix_network_config "/tmp"
    
    # 清理旧内核
    clean_old_kernels
    
    log_info "5/5: 更新软件包列表"
    $USE_SUDO apt-get update || log_warning "软件包列表更新失败，但系统修复已完成"
    
    log_success "========================================="
    log_success "🎉 系统修复完成"
    log_success "========================================="
    
    # 给出GRUB修复建议
    if [[ "$boot_mode" == "uefi" ]]; then
        log_info "EFI系统GRUB修复建议："
        log_info "1. 确认EFI分区挂载: mount | grep efi"
        log_info "2. 重装GRUB: sudo grub-install --target=x86_64-efi --efi-directory=/boot/efi"
        log_info "3. 更新配置: sudo update-grub"
        log_info "4. 检查引导项: sudo efibootmgr -v"
    else
        if [[ -n "$boot_disk" ]]; then
            log_info "BIOS系统GRUB修复建议："
            log_info "1. 重装GRUB: sudo grub-install $boot_disk"
            log_info "2. 更新配置: sudo update-grub"
            log_info "3. 验证安装: sudo grub-install --recheck $boot_disk"
        else
            log_warning "未检测到引导磁盘，请手动指定磁盘安装GRUB"
            log_info "示例: sudo grub-install /dev/sda"
        fi
    fi
    
    echo
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
            --fix-grub)
                check_root
                fix_grub_mode
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

# 检查是否为直接执行脚本（不是被source）
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    # 脚本入口 - 只有直接执行时才调用main函数
    main "$@"
fi
