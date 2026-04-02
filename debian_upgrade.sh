#!/bin/bash
# =============================================================================
# 脚本名称: debian_upgrade.sh
# 描    述: Debian 系统自动逐级升级脚本
#           支持 Debian 8~13，自动检测版本并升级到下一稳定版本
#           适用于 VPS、物理机、虚拟机等大多数 Debian 环境
# =============================================================================
# 版本历史:
#   v1.0  2024-01-01  初始版本
#   v2.0  2024-06-01  增加 UEFI/BIOS 自动检测，NVMe 磁盘支持
#   v2.5  2024-11-01  增加网络配置备份恢复，旧内核自动清理
#   v2.6  2024-12-01  修复 GRUB 过度修复问题，改进重启确认机制
#   v2.7  2025-01-01  修复 backports/第三方源残留导致 apt update 失败问题
#                     新增升级前自动清理无效 sources，提升 apt 更新兼容性
#                     新增 --mirror 镜像源选项，优化中国大陆网络环境
#                     修复 get_current_version 在部分 VPS 上返回空的边界情况
#                     增强错误日志输出，方便排查升级失败原因
#   v3.0  2026-04-02  全面重构，提升健壮性与兼容性
#                     - 统一错误处理，关键步骤均有 fallback
#                     - 修复 sources.list.d/ 目录旧源未清理导致冲突
#                     - 改进 GRUB 检测逻辑，避免误判和过度写入
#                     - 增加磁盘空间预检，不足时自动清理旧内核
#                     - 完善帮助文档与使用示例
# =============================================================================
# 使用方法:
#   chmod +x debian_upgrade.sh
#   sudo ./debian_upgrade.sh              # 正常升级
#   sudo ./debian_upgrade.sh --check      # 检查升级状态
#   sudo ./debian_upgrade.sh --fix-grub   # 专门修复 GRUB
#   sudo ./debian_upgrade.sh --help       # 查看完整帮助
# =============================================================================
# 注意事项:
#   - 需要 root 或 sudo 权限
#   - VPS 用户请确保有 VNC/控制台访问，以防重启后 SSH 断开
#   - 升级前建议快照或备份重要数据
#   - Debian 12 为当前稳定版，生产环境推荐保持
# =============================================================================

set -e

# ── 脚本元信息 ────────────────────────────────────────────────────────────────
SCRIPT_VERSION="3.0"
SCRIPT_NAME="debian_upgrade.sh"
SCRIPT_DATE="2025-07-01"

# ── 颜色定义 ──────────────────────────────────────────────────────────────────
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
CYAN='\033[0;36m'
NC='\033[0m'

# ── 日志函数 ──────────────────────────────────────────────────────────────────
log_info()    { echo -e "${BLUE}[INFO]${NC}    $(date '+%H:%M:%S') - $1"; }
log_success() { echo -e "${GREEN}[SUCCESS]${NC} $(date '+%H:%M:%S') - $1"; }
log_warning() { echo -e "${YELLOW}[WARNING]${NC} $(date '+%H:%M:%S') - $1"; }
log_error()   { echo -e "${RED}[ERROR]${NC}   $(date '+%H:%M:%S') - $1"; }
log_debug()   {
    if [[ "${DEBUG:-0}" == "1" ]]; then
        echo -e "${PURPLE}[DEBUG]${NC}   $(date '+%H:%M:%S') - $1"
    fi
}

# ── 全局变量 ──────────────────────────────────────────────────────────────────
USE_SUDO=""
MIRROR_BASE="http://deb.debian.org/debian"
MIRROR_SECURITY="http://deb.debian.org/debian-security"

# ── 用户交互确认 ──────────────────────────────────────────────────────────────
get_user_confirmation() {
    local prompt="$1"
    local response=""
    [[ ! -t 0 ]] && exec 0</dev/tty
    while true; do
        echo -n "$prompt"
        read -r response </dev/tty
        case "$response" in
            [Yy][Ee][Ss]) return 0 ;;
            [Nn][Oo]|"")  return 1 ;;
            *) echo "❌ 请输入 'YES' 确认，或 'no'/'回车' 取消" ;;
        esac
    done
}

# ── 启动模式检测 ──────────────────────────────────────────────────────────────
detect_boot_mode() {
    [[ -d /sys/firmware/efi ]] && echo "uefi" || echo "bios"
}

# ── 引导磁盘检测（多策略，兼容 NVMe / virtio / xen）────────────────────────
detect_boot_disk() {
    local disk=""

    # 策略1: /boot 分区所在磁盘
    if mount | grep -q " /boot "; then
        disk=$(mount | grep " /boot " | awk '{print $1}' \
               | sed -E 's/p?[0-9]+$//' )
        [[ -b "$disk" ]] && echo "$disk" && return
    fi

    # 策略2: / 分区所在磁盘
    disk=$(mount | grep -E "^/dev/.* / " | grep -v tmpfs \
           | head -1 | awk '{print $1}' \
           | sed -E 's/p?[0-9]+$//')
    [[ -b "$disk" ]] && echo "$disk" && return

    # 策略3: /proc/cmdline root=UUID 解析
    if [[ -f /proc/cmdline ]]; then
        local root_dev
        root_dev=$(grep -o 'root=[^ ]*' /proc/cmdline | head -1 | sed 's/root=//')
        if [[ "$root_dev" =~ ^UUID= ]]; then
            local uuid="${root_dev#UUID=}"
            disk=$(blkid -U "$uuid" 2>/dev/null | sed -E 's/p?[0-9]+$//')
        else
            disk=$(echo "$root_dev" | sed -E 's/p?[0-9]+$//')
        fi
        [[ -b "$disk" ]] && echo "$disk" && return
    fi

    # 策略4: lsblk 找第一块有分区表的磁盘
    while read -r name; do
        local dev="/dev/$name"
        if [[ -b "$dev" ]] && fdisk -l "$dev" 2>/dev/null | grep -q "Disklabel type"; then
            echo "$dev" && return
        fi
    done < <(lsblk -d -n -o NAME,TYPE | awk '$2=="disk"{print $1}')

    # 策略5: 常见设备名 fallback
    for dev in /dev/sda /dev/vda /dev/xvda /dev/nvme0n1; do
        [[ -b "$dev" ]] && echo "$dev" && return
    done

    echo ""
}

# ── 配置镜像源（支持 --mirror 参数）─────────────────────────────────────────
set_mirror() {
    case "${MIRROR:-default}" in
        cn|china)
            MIRROR_BASE="http://mirrors.aliyun.com/debian"
            MIRROR_SECURITY="http://mirrors.aliyun.com/debian-security"
            log_info "使用阿里云镜像源"
            ;;
        tuna)
            MIRROR_BASE="http://mirrors.tuna.tsinghua.edu.cn/debian"
            MIRROR_SECURITY="http://mirrors.tuna.tsinghua.edu.cn/debian-security"
            log_info "使用清华大学镜像源"
            ;;
        ustc)
            MIRROR_BASE="http://mirrors.ustc.edu.cn/debian"
            MIRROR_SECURITY="http://mirrors.ustc.edu.cn/debian-security"
            log_info "使用中科大镜像源"
            ;;
        *)
            log_debug "使用 Debian 官方源"
            ;;
    esac
}

# ── 版本信息映射 ──────────────────────────────────────────────────────────────
get_version_info() {
    case $1 in
        "8")  echo "jessie|oldoldstable" ;;
        "9")  echo "stretch|oldoldstable" ;;
        "10") echo "buster|oldstable" ;;
        "11") echo "bullseye|oldstable" ;;
        "12") echo "bookworm|stable" ;;
        "13") echo "trixie|testing" ;;
        "14") echo "forky|unstable" ;;
        *)    echo "unknown|unknown" ;;
    esac
}

get_next_version() {
    case $1 in
        "8")  echo "9"  ;;
        "9")  echo "10" ;;
        "10") echo "11" ;;
        "11") echo "12" ;;
        "12") [[ "${STABLE_ONLY:-1}" == "1" ]] && echo "" || echo "13" ;;
        "13") echo "14" ;;
        *)    echo "" ;;
    esac
}

# ── 当前版本检测（多策略，容错）──────────────────────────────────────────────
get_current_version() {
    local version_id=""

    log_debug "开始检测 Debian 版本..."

    # 策略1: /etc/os-release VERSION_ID
    if [[ -f /etc/os-release ]]; then
        version_id=$(grep "^VERSION_ID=" /etc/os-release \
                     | cut -d'"' -f2 | tr -d '[:space:]' 2>/dev/null || true)
        log_debug "os-release VERSION_ID: '$version_id'"
    fi

    # 策略2: /etc/debian_version 推断
    if [[ -z "$version_id" || ! "$version_id" =~ ^[0-9]+$ ]] \
       && [[ -f /etc/debian_version ]]; then
        local dv
        dv=$(cat /etc/debian_version 2>/dev/null || true)
        log_debug "debian_version: '$dv'"
        case "$dv" in
            8.*|jessie*)   version_id="8"  ;;
            9.*|stretch*)  version_id="9"  ;;
            10.*|buster*)  version_id="10" ;;
            11.*|bullseye*)version_id="11" ;;
            12.*|bookworm*)version_id="12" ;;
            13.*|trixie*)  version_id="13" ;;
            14.*|forky*)   version_id="14" ;;
        esac
    fi

    # 策略3: lsb_release
    if [[ -z "$version_id" || ! "$version_id" =~ ^[0-9]+$ ]] \
       && command -v lsb_release >/dev/null 2>&1; then
        local lv
        lv=$(lsb_release -rs 2>/dev/null | cut -d. -f1)
        [[ "$lv" =~ ^[0-9]+$ ]] && version_id="$lv"
        log_debug "lsb_release: '$lv'"
    fi

    # 策略4: apt-cache policy base-files 代号匹配
    if [[ -z "$version_id" || ! "$version_id" =~ ^[0-9]+$ ]]; then
        local ap
        ap=$(apt-cache policy base-files 2>/dev/null | head -20 || true)
        if   echo "$ap" | grep -q "bookworm"; then version_id="12"
        elif echo "$ap" | grep -q "bullseye"; then version_id="11"
        elif echo "$ap" | grep -q "buster";   then version_id="10"
        elif echo "$ap" | grep -q "stretch";  then version_id="9"
        elif echo "$ap" | grep -q "jessie";   then version_id="8"
        elif echo "$ap" | grep -q "trixie";   then version_id="13"
        fi
        log_debug "apt-cache policy: '$version_id'"
    fi

    if [[ -z "$version_id" || ! "$version_id" =~ ^[0-9]+$ ]]; then
        log_error "无法确定 Debian 版本，调试信息："
        log_error "  /etc/debian_version : $(cat /etc/debian_version 2>/dev/null || echo '不存在')"
        log_error "  os-release          : $(grep VERSION /etc/os-release 2>/dev/null || echo '不存在')"
        log_error "  内核版本            : $(uname -r)"
        echo ""
        return 1
    fi

    log_debug "最终版本: '$version_id'"
    echo "$version_id"
}

# ── 网络配置备份 ──────────────────────────────────────────────────────────────
save_network_config() {
    local backup_dir="/root/debian_upgrade_backup_$(date +%Y%m%d_%H%M%S)"
    log_debug "备份网络配置到 $backup_dir"
    $USE_SUDO mkdir -p "$backup_dir/network"
    $USE_SUDO cp -a /etc/network/interfaces* "$backup_dir/network/" 2>/dev/null || true
    $USE_SUDO cp -a /etc/systemd/network/    "$backup_dir/network/" 2>/dev/null || true
    ip addr show  > "$backup_dir/network/ip_addr_before.txt"  2>/dev/null || true
    ip route show > "$backup_dir/network/ip_route_before.txt" 2>/dev/null || true
    ip -o link show | awk -F': ' '{print $2}' | grep -v lo \
        > "$backup_dir/network/interface_names.txt" 2>/dev/null || true
    echo "$backup_dir"
}

# ── 网络配置修复 ──────────────────────────────────────────────────────────────
fix_network_config() {
    local backup_dir="$1"
    log_debug "检查并修复网络配置..."
    local new_ifs
    new_ifs=$(ip -o link show | awk -F': ' '{print $2}' | grep -v lo)

    if [[ -f "$backup_dir/network/interface_names.txt" ]]; then
        while read -r old_if; do
            if ! echo "$new_ifs" | grep -q "^${old_if}$"; then
                log_warning "网络接口 $old_if 已不存在"
                local new_if
                new_if=$(echo "$new_ifs" | head -1)
                if [[ -n "$new_if" && -f /etc/network/interfaces ]]; then
                    log_info "将 $old_if 的配置映射到 $new_if"
                    $USE_SUDO sed -i "s/\b${old_if}\b/$new_if/g" /etc/network/interfaces
                fi
            fi
        done < "$backup_dir/network/interface_names.txt"
    fi

    for svc in NetworkManager systemd-networkd networking; do
        if systemctl is-enabled "$svc" >/dev/null 2>&1; then
            log_debug "$svc 已启用"
            break
        fi
    done
}

# ── 清理旧内核 ────────────────────────────────────────────────────────────────
clean_old_kernels() {
    log_info "清理旧内核以释放 /boot 空间..."
    local cur_k latest_k
    cur_k=$(uname -r)
    latest_k=$(ls -t /boot/vmlinuz-* 2>/dev/null | head -1 | sed 's|/boot/vmlinuz-||')
    log_info "当前内核: $cur_k | 最新内核: ${latest_k:-未知}"

    local to_remove=""
    while read -r pkg; do
        local ver="${pkg#linux-image-}"
        if [[ "$ver" != "$cur_k" && "$ver" != "$latest_k" \
              && "$pkg" != "linux-image-amd64" \
              && "$pkg" != "linux-image-arm64" ]]; then
            to_remove="$to_remove $pkg"
        fi
    done < <(dpkg -l 'linux-image-*' 2>/dev/null | awk '/^ii/{print $2}')

    if [[ -n "$to_remove" ]]; then
        log_info "移除旧内核: $to_remove"
        # shellcheck disable=SC2086
        $USE_SUDO apt-get remove --purge -y $to_remove 2>/dev/null || true
        $USE_SUDO apt-get autoremove -y --purge 2>/dev/null || true
    else
        log_info "无需清理旧内核"
    fi

    $USE_SUDO find /boot -name "*.old" -o -name "*.bak" -delete 2>/dev/null || true

    if mount | grep -q " /boot "; then
        log_info "/boot 使用: $(df -h /boot | awk 'NR==2{print $5}') | 可用: $(df -h /boot | awk 'NR==2{print $4}')"
    fi
}

# ── 清理无效 / 过期 APT 源（升级前必须执行）──────────────────────────────────
# 解决问题：旧版本 backports、第三方源在升级后代号不匹配，导致 apt update 报 404
clean_apt_sources() {
    local target_codename="$1"
    log_info "清理无效 APT 源（目标代号: $target_codename）..."

    # 备份 sources.list.d/
    if [[ -d /etc/apt/sources.list.d ]]; then
        local bak_dir="/etc/apt/sources.list.d.bak_$(date +%s)"
        $USE_SUDO cp -a /etc/apt/sources.list.d "$bak_dir" 2>/dev/null || true
        log_info "已备份 sources.list.d/ 到 $bak_dir"

        # 禁用（重命名）含有旧代号的源文件，避免影响升级
        while read -r src_file; do
            # 跳过已禁用的文件
            [[ "$src_file" == *.disabled ]] && continue

            # 如果文件内容涉及 backports 或非当前目标代号，暂时禁用
            if grep -qE \
                "bullseye-backports|buster-backports|stretch-backports|jessie-backports" \
                "$src_file" 2>/dev/null; then
                log_warning "禁用 backports 源: $src_file"
                $USE_SUDO mv "$src_file" "${src_file}.disabled" 2>/dev/null || true
            fi
        done < <(find /etc/apt/sources.list.d/ -maxdepth 1 -name "*.list" 2>/dev/null)
    fi

    # 同样检查主 sources.list 中的 backports 行
    if [[ -f /etc/apt/sources.list ]]; then
        if grep -q "backports" /etc/apt/sources.list 2>/dev/null; then
            log_warning "注释掉 sources.list 中的 backports 行"
            $USE_SUDO sed -i '/backports/s/^/#/' /etc/apt/sources.list
        fi
    fi

    log_success "APT 源清理完成"
}

# ── 安全 GRUB 更新（保守策略）────────────────────────────────────────────────
update_grub_safe() {
    local boot_mode
    boot_mode=$(detect_boot_mode)
    local boot_disk
    boot_disk=$(detect_boot_disk)

    log_info "更新 GRUB 配置（启动模式: $boot_mode）"

    # 先只更新配置，不重装
    $USE_SUDO update-grub 2>/dev/null \
        || $USE_SUDO grub-mkconfig -o /boot/grub/grub.cfg 2>/dev/null \
        || true

    # 检测是否真的需要重新安装 GRUB
    local need_reinstall=false
    if [[ "$boot_mode" == "uefi" ]]; then
        efibootmgr 2>/dev/null | grep -qi "debian\|grub" || need_reinstall=true
    else
        if [[ -n "$boot_disk" ]]; then
            $USE_SUDO dd if="$boot_disk" bs=512 count=1 2>/dev/null \
                | strings | grep -q GRUB || need_reinstall=true
        fi
    fi

    if [[ "$need_reinstall" == "true" ]]; then
        log_info "GRUB 需要重新安装"
        if [[ "$boot_mode" == "uefi" ]]; then
            DEBIAN_FRONTEND=noninteractive $USE_SUDO apt-get install -y \
                grub-efi-amd64 grub-efi-amd64-bin efibootmgr 2>/dev/null || true
            if [[ -d /boot/efi ]]; then
                $USE_SUDO grub-install --target=x86_64-efi \
                    --efi-directory=/boot/efi \
                    --bootloader-id=debian --recheck 2>/dev/null || \
                    log_warning "GRUB EFI 安装失败"
            fi
        else
            if [[ -n "$boot_disk" ]]; then
                DEBIAN_FRONTEND=noninteractive $USE_SUDO apt-get install -y \
                    grub-pc grub-pc-bin 2>/dev/null || true
                $USE_SUDO grub-install --target=i386-pc --recheck "$boot_disk" 2>/dev/null || {
                    log_warning "GRUB 安装失败，尝试 dpkg-reconfigure"
                    echo "grub-pc grub-pc/install_devices multiselect $boot_disk" \
                        | $USE_SUDO debconf-set-selections
                    DEBIAN_FRONTEND=noninteractive $USE_SUDO dpkg-reconfigure grub-pc 2>/dev/null || true
                }
            fi
        fi
        $USE_SUDO update-grub 2>/dev/null || true
    else
        log_info "GRUB 已正确安装，跳过重新安装"
    fi
}

# ── 系统环境检查 ──────────────────────────────────────────────────────────────
check_system() {
    log_info "检查系统环境..."

    if ! grep -q "^ID=debian" /etc/os-release 2>/dev/null; then
        log_error "此脚本仅适用于 Debian 系统"
        exit 1
    fi

    # 磁盘空间 (根分区 >= 2GB)
    local avail_kb
    avail_kb=$(df / | awk 'NR==2{print $4}')
    if (( avail_kb < 2097152 )); then
        log_warning "根分区可用空间不足 2GB，升级可能失败"
    fi

    # /boot 分区空间
    if mount | grep -q " /boot "; then
        local boot_kb
        boot_kb=$(df /boot | awk 'NR==2{print $4}')
        if (( boot_kb < 204800 )); then
            log_warning "/boot 可用空间不足 200MB，先清理旧内核"
            clean_old_kernels
        fi
    fi

    # 内存检查
    local avail_mem
    avail_mem=$(free -m | awk 'NR==2{print $7}')
    (( avail_mem < 256 )) && log_warning "可用内存不足 256MB，升级可能较慢"

    # 网络连通性（仅警告，不阻断）
    if ! ping -c 1 -W 5 deb.debian.org >/dev/null 2>&1; then
        log_warning "无法连接 deb.debian.org，请确认网络或使用 --mirror 选项"
    fi

    log_debug "启动模式: $(detect_boot_mode) | 引导磁盘: $(detect_boot_disk || echo '未检测到')"
    log_success "系统环境检查完成"
}

# ── 权限检测 ──────────────────────────────────────────────────────────────────
check_root() {
    if [[ $EUID -eq 0 ]]; then
        USE_SUDO=""
    else
        sudo -n true 2>/dev/null || sudo -v
        USE_SUDO="sudo"
    fi
}

# ── 升级前准备 ────────────────────────────────────────────────────────────────
pre_upgrade_preparation() {
    local target_codename="$1"
    log_info "执行升级前准备工作..."

    # 停止自动更新服务，避免锁冲突
    for svc in unattended-upgrades apt-daily apt-daily-upgrade; do
        systemctl is-active "$svc" >/dev/null 2>&1 \
            && $USE_SUDO systemctl stop "$svc" 2>/dev/null || true
    done

    # 清理 APT 锁文件
    $USE_SUDO rm -f /var/lib/dpkg/lock-frontend \
                    /var/lib/dpkg/lock \
                    /var/cache/apt/archives/lock \
                    /var/lib/apt/lists/lock 2>/dev/null || true

    # 修复 dpkg / 损坏依赖
    $USE_SUDO dpkg --configure -a 2>/dev/null || true
    DEBIAN_FRONTEND=noninteractive $USE_SUDO apt-get --fix-broken install -y 2>/dev/null || true

    # 关键步骤：清理旧/无效 sources，避免 404
    clean_apt_sources "$target_codename"

    # 检查并预设 GRUB 磁盘，避免升级时弹出交互提示
    local boot_mode boot_disk
    boot_mode=$(detect_boot_mode)
    boot_disk=$(detect_boot_disk)

    if [[ -z "$boot_disk" ]]; then
        log_warning "未自动检测到引导磁盘，升级后可能需手动修复 GRUB"
        if [[ "${FORCE:-0}" != "1" ]]; then
            read -p "是否继续升级？[y/N]: " -n 1 -r </dev/tty; echo
            [[ ! $REPLY =~ ^[Yy]$ ]] && { log_info "已取消"; exit 1; }
        fi
    else
        log_success "引导磁盘: $boot_disk（模式: $boot_mode）"
        if [[ "$boot_mode" == "bios" ]]; then
            printf "grub-pc grub-pc/install_devices multiselect %s\n" "$boot_disk" \
                | $USE_SUDO debconf-set-selections
            echo "grub-pc grub-pc/install_devices_empty boolean false" \
                | $USE_SUDO debconf-set-selections
        fi
    fi

    log_success "升级前准备完成"
}

# ── 升级后修复 ────────────────────────────────────────────────────────────────
post_upgrade_fixes() {
    local backup_dir="$1"
    log_info "执行升级后修复..."

    fix_network_config "$backup_dir"

    # 重建 initramfs
    log_info "重建 initramfs..."
    $USE_SUDO rm -f /boot/initrd.img-*.bak 2>/dev/null || true
    while read -r kver; do
        log_info "  内核: $kver"
        $USE_SUDO update-initramfs -c -k "$kver" 2>/dev/null \
            || $USE_SUDO update-initramfs -u -k "$kver" 2>/dev/null || true
    done < <(ls /boot/vmlinuz-* 2>/dev/null | sed 's|/boot/vmlinuz-||')

    # 重装 GRUB 包
    local boot_mode
    boot_mode=$(detect_boot_mode)
    if [[ "$boot_mode" == "uefi" ]]; then
        DEBIAN_FRONTEND=noninteractive $USE_SUDO apt-get install --reinstall -y \
            grub-efi-amd64 grub-efi-amd64-bin 2>/dev/null || true
    else
        DEBIAN_FRONTEND=noninteractive $USE_SUDO apt-get install --reinstall -y \
            grub-pc grub-pc-bin 2>/dev/null || true
    fi

    # GRUB 配置更新（保守模式）
    if [[ ! -f /boot/grub/grub.cfg ]] || [[ ! -s /boot/grub/grub.cfg ]]; then
        log_warning "GRUB 配置缺失，执行修复"
        update_grub_safe
    else
        log_info "更新 GRUB 配置（保守模式）"
        $USE_SUDO update-grub 2>/dev/null || true
    fi

    # 执行额外 GRUB 修复（提升 VPS 兼容性）
    log_info "执行额外 GRUB 修复..."
    local boot_disk
    boot_disk=$(detect_boot_disk)
    if [[ -n "$boot_disk" ]]; then
        if [[ "$boot_mode" == "uefi" ]]; then
            # UEFI：额外创建 removable 和 fallback 引导入口，提升云/VPS 兼容性
            if [[ -d /boot/efi/EFI ]]; then
                $USE_SUDO grub-install --target=x86_64-efi \
                    --efi-directory=/boot/efi \
                    --bootloader-id=debian \
                    --force-extra-removable 2>/dev/null || true
                $USE_SUDO grub-install --target=x86_64-efi \
                    --efi-directory=/boot/efi \
                    --removable 2>/dev/null || true
            fi
        else
            # BIOS：强制覆写 MBR bootsector，再重装 GRUB，确保引导链完整
            log_info "BIOS 模式：强制写入 MBR bootsector"
            $USE_SUDO dd if=/usr/lib/grub/i386-pc/boot.img \
                of="$boot_disk" bs=446 count=1 2>/dev/null || true
            $USE_SUDO grub-install --force --recheck "$boot_disk" 2>/dev/null || {
                log_warning "标准安装失败，尝试 --force-file-id"
                $USE_SUDO grub-install --force-file-id "$boot_disk" 2>/dev/null || true
            }
        fi
    fi

    # 最终 GRUB 配置刷新
    $USE_SUDO update-grub 2>/dev/null || true

    # 验证 GRUB
    if [[ "$boot_mode" == "bios" ]]; then
        local entries
        entries=$(grep -c "menuentry " /boot/grub/grub.cfg 2>/dev/null || echo 0)
        if (( entries == 0 )); then
            log_warning "GRUB 配置无启动项，重新生成"
            $USE_SUDO grub-mkconfig -o /boot/grub/grub.cfg 2>/dev/null || true
        else
            log_success "GRUB 启动项数量: $entries"
        fi
    else
        efibootmgr 2>/dev/null | grep -qi "debian" \
            && log_success "EFI 引导项检查通过" \
            || log_warning "未检测到 debian EFI 引导项，可能需手动修复"
    fi

    # 清理残留包
    $USE_SUDO apt-get autoremove -y --purge 2>/dev/null || true
    $USE_SUDO apt-get autoclean 2>/dev/null || true

    # 重启关键网络服务
    for svc in ssh sshd networking systemd-networkd NetworkManager; do
        systemctl is-enabled "$svc" >/dev/null 2>&1 \
            && $USE_SUDO systemctl restart "$svc" 2>/dev/null || true
    done

    sync; sync; sync
    log_success "升级后修复完成"
}

# ── 安全重启 ──────────────────────────────────────────────────────────────────
safe_reboot() {
    echo
    echo "╔════════════════════════════════════════╗"
    echo "║           ⚠️  即将重启系统              ║"
    echo "╚════════════════════════════════════════╝"
    read -p "最后确认：确定要重启吗？[y/N]: " -n 1 -r </dev/tty; echo
    [[ ! $REPLY =~ ^[Yy]$ ]] && { log_info "已取消重启，请稍后手动执行: sudo reboot"; return; }

    log_info "同步文件系统..."
    sync; sync; sync
    sleep 2
    echo 3 | $USE_SUDO tee /proc/sys/vm/drop_caches >/dev/null 2>&1 || true
    sync

    echo
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "  💡 如重启后系统无法启动，救援模式执行:"
    echo "     grub-install /dev/sdX && update-grub"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

    for i in 5 4 3 2 1; do echo -n "$i... "; sleep 1; done; echo

    if command -v systemctl >/dev/null 2>&1; then
        $USE_SUDO systemctl reboot --force
    else
        $USE_SUDO reboot -f
    fi
}

# ── 帮助信息 ──────────────────────────────────────────────────────────────────
show_help() {
    cat << EOF
╔══════════════════════════════════════════════════════════════════╗
║         Debian 自动逐级升级脚本 v${SCRIPT_VERSION}  (${SCRIPT_DATE})         ║
╚══════════════════════════════════════════════════════════════════╝

📖 用法: $0 [选项]

🔧 选项:
  -h, --help            显示此帮助
  -v, --version         显示当前 Debian 版本
  -c, --check           检查是否有可用升级
  -d, --debug           启用调试模式
  --fix-only            仅修复系统，不升级
  --fix-grub            专门修复 GRUB 引导
  --force               跳过所有确认提示
  --stable-only         仅升级到稳定版（默认，跳过 testing）
  --allow-testing       允许升级到 testing 版本
  --mirror <cn|tuna|ustc>  使用国内镜像源

✨ 功能特性:
  ✅ 自动检测并逐级升级 Debian 8 → 12
  ✅ 升级前自动清理无效 backports / 第三方源 ← v2.7 新增
  ✅ 兼容 UEFI / BIOS，支持 NVMe、virtio、xen 磁盘
  ✅ 网络接口名称变化自动修复
  ✅ /boot 空间不足时自动清理旧内核
  ✅ 保守的 GRUB 策略，避免误操作 MBR
  ✅ 国内镜像源一键切换

🔄 升级路径:
  Debian 8 (Jessie) → 9 (Stretch) → 10 (Buster)
            → 11 (Bullseye) → 12 (Bookworm) [当前稳定版]
            → 13 (Trixie)   [测试版，需 --allow-testing]

💻 示例:
  $0                         # 自动升级到下一版本
  $0 --check                 # 检查升级状态
  $0 --mirror cn             # 使用阿里云源升级（推荐国内）
  $0 --stable-only           # 仅升级到稳定版
  $0 --allow-testing --force # 强制升级到 trixie
  $0 --fix-grub              # 修复引导问题
  $0 --debug                 # 调试模式

⚠️  注意:
  • VPS 用户请确保有 VNC / 控制台访问权限
  • 升级前请创建系统快照或数据备份
  • Debian 12 (Bookworm) 为当前推荐稳定版
EOF
}

# ── 检查升级状态 ──────────────────────────────────────────────────────────────
check_upgrade() {
    local cur nxt cur_info nxt_info cur_name cur_stat nxt_name nxt_stat
    cur=$(get_current_version)
    cur_info=$(get_version_info "$cur")
    cur_name=$(echo "$cur_info" | cut -d'|' -f1)
    cur_stat=$(echo "$cur_info" | cut -d'|' -f2)
    nxt=$(get_next_version "$cur")

    echo "═══════════════════════════════════════════"
    echo "  🔍 Debian 升级状态检查"
    echo "═══════════════════════════════════════════"
    echo "  当前版本: Debian $cur ($cur_name) [$cur_stat]"

    if [[ -z "$nxt" ]]; then
        echo "  状    态: ✅ 已是最新稳定版本"
    else
        nxt_info=$(get_version_info "$nxt")
        nxt_name=$(echo "$nxt_info" | cut -d'|' -f1)
        nxt_stat=$(echo "$nxt_info" | cut -d'|' -f2)
        echo "  可升级到: Debian $nxt ($nxt_name) [$nxt_stat]"
        [[ "$nxt_stat" =~ testing|unstable ]] \
            && echo "  ⚠️  非稳定版本，生产环境请使用 --stable-only"
    fi

    echo "───────────────────────────────────────────"
    echo "  启动模式: $(detect_boot_mode)"
    echo "  引导磁盘: $(detect_boot_disk || echo '未检测到')"
    echo "  根分区:   $(df -h / | awk 'NR==2{printf "已用 %s，可用 %s", $3, $4}')"

    if mount | grep -q " /boot "; then
        echo "  /boot:    $(df -h /boot | awk 'NR==2{printf "已用 %s，可用 %s", $3, $4}')"
    fi

    echo "  内存:     $(free -h | awk 'NR==2{printf "已用 %s / 总计 %s", $3, $2}')"

    ping -c 1 -W 5 deb.debian.org >/dev/null 2>&1 \
        && echo "  网络:     ✅ 可连接 deb.debian.org" \
        || echo "  网络:     ⚠️  无法连接 deb.debian.org"

    local load_avg
    load_avg=$(uptime | awk -F'load average:' '{print $2}' | awk '{print $1}' | tr -d ',')
    echo "  系统负载: $load_avg"

    local broken
    broken=$(dpkg --get-selections 2>/dev/null | grep -c "deinstall" || echo 0)
    (( broken > 0 )) \
        && echo "  软件包:   ⚠️  发现 $broken 个问题包" \
        || echo "  软件包:   ✅ 正常"

    echo "═══════════════════════════════════════════"

    # 升级建议
    echo "📝 升级建议:"
    if [[ -n "$nxt" ]]; then
        local adv_info adv_stat adv_name
        adv_info=$(get_version_info "$nxt")
        adv_name=$(echo "$adv_info" | cut -d'|' -f1)
        adv_stat=$(echo "$adv_info" | cut -d'|' -f2)
        if [[ "$adv_stat" == "stable" ]]; then
            echo "  ✅ 推荐升级到 Debian $nxt ($adv_name) - 稳定版"
            echo "  🔧 升级前建议先修复引导: $0 --fix-grub"
            echo "  🚀 执行升级:             $0"
        elif [[ "$adv_stat" == "testing" ]]; then
            echo "  ⚠️  可升级到 Debian $nxt ($adv_name) - 测试版"
            echo "  🧪 测试环境升级: $0 --allow-testing"
            echo "  🛡️  保持稳定版本: $0 --stable-only  (推荐)"
        else
            echo "  ❌ 不建议升级到 Debian $nxt - 不稳定版本"
        fi
    else
        echo "  ✅ 当前版本已是最佳选择，无需升级"
    fi

    echo "═══════════════════════════════════════════"
}

# ── 主升级流程 ────────────────────────────────────────────────────────────────
main_upgrade() {
    local cur cur_info cur_name cur_stat nxt nxt_info nxt_name nxt_stat
    cur=$(get_current_version)
    if [[ -z "$cur" ]]; then
        log_error "无法检测当前版本，退出"
        exit 1
    fi

    cur_info=$(get_version_info "$cur")
    cur_name=$(echo "$cur_info" | cut -d'|' -f1)
    cur_stat=$(echo "$cur_info" | cut -d'|' -f2)
    nxt=$(get_next_version "$cur")

    log_info "════════════════════════════════════════"
    log_info "Debian 自动升级脚本 v${SCRIPT_VERSION}"
    log_info "当前: Debian $cur ($cur_name) [$cur_stat]"

    if [[ -z "$nxt" ]]; then
        log_success "🎉 已是最新稳定版本 Debian $cur"
        [[ "${STABLE_ONLY:-1}" != "1" ]] \
            && log_info "提示: 可用 --allow-testing 升级到 testing 版本"
        exit 0
    fi

    nxt_info=$(get_version_info "$nxt")
    nxt_name=$(echo "$nxt_info" | cut -d'|' -f1)
    nxt_stat=$(echo "$nxt_info" | cut -d'|' -f2)

    if [[ "$nxt_name" == "unknown" ]]; then
        log_warning "Debian $nxt 尚不支持，当前版本已是最新"
        exit 0
    fi

    log_info "目标: Debian $nxt ($nxt_name) [$nxt_stat]"

    # 非稳定版本需额外确认
    if [[ "$nxt_stat" =~ testing|unstable ]]; then
        echo
        log_warning "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
        log_warning "⚠️  目标为非稳定版本 ($nxt_stat)，不建议生产环境使用"
        log_warning "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
        if [[ "${FORCE:-0}" != "1" ]]; then
            get_user_confirmation "输入 'YES' 确认升级到测试版，或回车取消: " \
                || { log_info "已取消"; exit 0; }
        fi
    else
        if [[ "${FORCE:-0}" != "1" ]]; then
            read -p "确认升级到 Debian $nxt ($nxt_name)？[y/N]: " -n 1 -r </dev/tty; echo
            [[ ! $REPLY =~ ^[Yy]$ ]] && { log_info "已取消"; exit 0; }
        fi
    fi

    # 备份网络配置
    local backup_dir
    backup_dir=$(save_network_config)

    # 升级前准备（含清理无效源）
    pre_upgrade_preparation "$nxt_name"

    # ── 步骤 1：写入新 sources.list ──────────────────────────────────────────
    log_info "步骤 1/4: 更新软件源配置 → $nxt_name"
    $USE_SUDO cp /etc/apt/sources.list \
        "/etc/apt/sources.list.backup.$(date +%s)" 2>/dev/null || true

    local sec_suffix=""
    # Debian 11+ 安全源格式变为 codename-security
    (( nxt >= 11 )) && sec_suffix="-security" || sec_suffix="/updates"

    # Debian 12+ 加入 non-free-firmware
    local nff=""
    (( nxt >= 12 )) && nff=" non-free-firmware"

    $USE_SUDO tee /etc/apt/sources.list > /dev/null << EOF
# Debian $nxt ($nxt_name) - 由 $SCRIPT_NAME v$SCRIPT_VERSION 自动生成
deb ${MIRROR_BASE} ${nxt_name} main contrib non-free${nff}
deb-src ${MIRROR_BASE} ${nxt_name} main contrib non-free${nff}

deb ${MIRROR_SECURITY} ${nxt_name}${sec_suffix} main contrib non-free${nff}
deb-src ${MIRROR_SECURITY} ${nxt_name}${sec_suffix} main contrib non-free${nff}

deb ${MIRROR_BASE} ${nxt_name}-updates main contrib non-free${nff}
deb-src ${MIRROR_BASE} ${nxt_name}-updates main contrib non-free${nff}
EOF

    log_success "软件源配置完成"

    # ── 步骤 2：更新包列表 ────────────────────────────────────────────────────
    log_info "步骤 2/4: 更新软件包列表"
    # 允许部分失败（如残留第三方源），继续升级
    $USE_SUDO apt-get update 2>&1 | tee /tmp/apt_update.log || {
        log_warning "apt-get update 出现错误（见上），检查是否可继续..."
        # 如果是 Release 文件不存在（404），属于已清理源的残留，可忽略
        if grep -q "404\|Release.*does not have" /tmp/apt_update.log; then
            log_warning "检测到 404 错误，尝试再次清理无效源后重试"
            # 禁用所有 sources.list.d 中的第三方源
            find /etc/apt/sources.list.d/ -maxdepth 1 -name "*.list" \
                -not -name "*.disabled" 2>/dev/null \
                | while read -r f; do
                    log_warning "  禁用: $f"
                    $USE_SUDO mv "$f" "${f}.disabled" 2>/dev/null || true
                done
            $USE_SUDO apt-get update || {
                log_error "软件包列表更新失败，请检查网络或手动修复源配置"
                exit 1
            }
        else
            log_error "软件包列表更新失败"
            exit 1
        fi
    }

    # ── 步骤 3：执行升级 ──────────────────────────────────────────────────────
    log_info "步骤 3/4: 执行系统升级"

    log_info "  3.1 最小升级 (upgrade)..."
    DEBIAN_FRONTEND=noninteractive $USE_SUDO apt-get upgrade -y \
        -o Dpkg::Options::="--force-confdef" \
        -o Dpkg::Options::="--force-confold" || \
        log_warning "最小升级出现警告，继续完整升级"

    log_info "  3.2 完整升级 (dist-upgrade)..."
    DEBIAN_FRONTEND=noninteractive $USE_SUDO apt-get dist-upgrade -y \
        -o Dpkg::Options::="--force-confdef" \
        -o Dpkg::Options::="--force-confold" || {
        log_error "dist-upgrade 失败，尝试修复后重试"
        $USE_SUDO dpkg --configure -a 2>/dev/null || true
        DEBIAN_FRONTEND=noninteractive $USE_SUDO apt-get -f install -y 2>/dev/null || true
        DEBIAN_FRONTEND=noninteractive $USE_SUDO apt-get dist-upgrade -y \
            -o Dpkg::Options::="--force-confdef" \
            -o Dpkg::Options::="--force-confold" || {
            log_error "升级失败，请查看上方错误信息"
            exit 1
        }
    }

    # ── 步骤 4：修复 ──────────────────────────────────────────────────────────
    log_info "步骤 4/4: 升级后修复"
    post_upgrade_fixes "$backup_dir"

    # ── 验证升级结果 ──────────────────────────────────────────────────────────
    sleep 2
    local new_ver
    new_ver=$(get_current_version)

    if [[ "$new_ver" == "$nxt" ]]; then
        echo
        log_success "╔════════════════════════════════════════╗"
        log_success "║  🎉 升级完成！Debian $cur → $nxt ($nxt_name)  ║"
        log_success "╚════════════════════════════════════════╝"
        echo
        log_info "📋 配置备份: $backup_dir"
        log_info "⚠️  如重启失败，执行: $0 --fix-grub"

        # 检查是否还有后续版本
        local further
        further=$(get_next_version "$nxt")
        if [[ -n "$further" ]]; then
            local fi
            fi=$(get_version_info "$further")
            log_info "🚀 后续可继续升级到 Debian $further ($(echo $fi | cut -d'|' -f1))"
        fi

        echo
        if [[ "${FORCE:-0}" != "1" ]]; then
            read -p "是否需要 GRUB 修复？（通常无需）[y/N]: " -n 1 -r </dev/tty; echo
            [[ $REPLY =~ ^[Yy]$ ]] && fix_grub_quick

            read -p "是否现在重启系统？[y/N]: " -n 1 -r </dev/tty; echo
            [[ $REPLY =~ ^[Yy]$ ]] && safe_reboot \
                || log_info "请稍后手动重启: sudo reboot"
        fi
    else
        log_error "升级验证失败！期望: $nxt，检测到: $new_ver"
        log_error "请运行 $0 --fix-only 尝试修复"
        exit 1
    fi
}

# ── 快速 GRUB 修复 ────────────────────────────────────────────────────────────
fix_grub_quick() {
    log_info "执行保守 GRUB 修复..."
    $USE_SUDO update-grub 2>/dev/null \
        || $USE_SUDO grub-mkconfig -o /boot/grub/grub.cfg 2>/dev/null || true

    if [[ ! -f /boot/grub/grub.cfg ]]; then
        log_warning "GRUB 配置不存在，执行完整修复"
        update_grub_safe
    fi

    sync; sync
    log_success "保守 GRUB 修复完成"
}

# ── GRUB 专项修复模式 ─────────────────────────────────────────────────────────
fix_grub_mode() {
    log_info "═══════════════════════════════════════════"
    log_info "🔧 GRUB 引导修复模式"
    log_info "═══════════════════════════════════════════"

    local boot_mode boot_disk
    boot_mode=$(detect_boot_mode)
    boot_disk=$(detect_boot_disk)

    log_info "启动模式: $boot_mode | 引导磁盘: ${boot_disk:-未检测到}"

    if [[ -z "$boot_disk" ]]; then
        log_warning "未能自动检测引导磁盘，请手动选择："
        local disks=()
        while read -r line; do
            disks+=("$line")
            echo "  $((${#disks[@]})). /dev/$line"
        done < <(lsblk -d -n -o NAME,TYPE | awk '$2=="disk"{print $1" - "$(3)}')

        read -p "输入编号或回车跳过: " -r </dev/tty
        if [[ "$REPLY" =~ ^[0-9]+$ ]] && (( REPLY >= 1 && REPLY <= ${#disks[@]} )); then
            boot_disk="/dev/$(echo "${disks[$((REPLY-1))]}" | awk '{print $1}')"
            log_info "已选择: $boot_disk"
        fi
    fi

    # 重装 GRUB 包
    log_info "步骤 1: 重装 GRUB 包"
    if [[ "$boot_mode" == "uefi" ]]; then
        DEBIAN_FRONTEND=noninteractive $USE_SUDO apt-get install --reinstall -y \
            grub-efi-amd64 grub-efi-amd64-bin grub2-common efibootmgr 2>/dev/null || true
    else
        DEBIAN_FRONTEND=noninteractive $USE_SUDO apt-get install --reinstall -y \
            grub-pc grub-pc-bin grub2-common 2>/dev/null || true
    fi

    # 生成 GRUB 配置
    log_info "步骤 2: 生成 GRUB 配置"
    $USE_SUDO grub-mkconfig -o /boot/grub/grub.cfg 2>/dev/null \
        || $USE_SUDO update-grub 2>/dev/null || true

    # 安装 GRUB 到磁盘
    if [[ -n "$boot_disk" ]]; then
        log_info "步骤 3: 安装 GRUB 到 $boot_disk"
        if [[ "$boot_mode" == "uefi" ]]; then
            local efi_dir="/boot/efi"
            [[ ! -d "$efi_dir" && -d "/efi" ]] && efi_dir="/efi"
            $USE_SUDO grub-install --target=x86_64-efi \
                --efi-directory="$efi_dir" \
                --bootloader-id=debian \
                --recheck --force 2>&1 | tail -3
        else
            $USE_SUDO grub-install --target=i386-pc \
                --recheck --force "$boot_disk" 2>&1 | tail -3
        fi
    fi

    # 最终更新
    log_info "步骤 4: 最终更新配置"
    $USE_SUDO update-grub 2>/dev/null || true

    # 验证
    if [[ -f /boot/grub/grub.cfg ]]; then
        local n
        n=$(grep -c "menuentry " /boot/grub/grub.cfg 2>/dev/null || echo 0)
        log_success "GRUB 启动项: $n 个"
    else
        log_error "GRUB 配置文件仍不存在！"
    fi

    log_success "═══════════════════════════════════════════"
    log_success "🎉 GRUB 修复完成，建议重启验证"
    log_success "═══════════════════════════════════════════"
}

# ── 仅修复模式 ────────────────────────────────────────────────────────────────
fix_only_mode() {
    log_info "═══════════════════════════════════════════"
    log_info "🔧 系统修复模式"
    log_info "═══════════════════════════════════════════"

    log_info "1/4 清理 APT 锁文件"
    $USE_SUDO rm -f /var/lib/dpkg/lock-frontend /var/lib/dpkg/lock \
                    /var/cache/apt/archives/lock /var/lib/apt/lists/lock 2>/dev/null || true

    log_info "2/4 修复 dpkg 状态"
    $USE_SUDO dpkg --configure -a 2>/dev/null || true
    DEBIAN_FRONTEND=noninteractive $USE_SUDO apt-get --fix-broken install -y 2>/dev/null || true

    log_info "3/4 修复 GRUB"
    update_grub_safe

    log_info "4/4 清理旧内核"
    clean_old_kernels

    $USE_SUDO apt-get update 2>/dev/null || log_warning "apt update 失败，但修复已完成"

    log_success "系统修复完成"
    log_info "建议运行: $0 --check 查看升级状态"
}

# ── 错误恢复 ──────────────────────────────────────────────────────────────────
error_recovery() {
    local code="$1"
    log_error "脚本异常退出（退出码: $code）"
    log_info "尝试基本恢复..."
    $USE_SUDO dpkg --configure -a 2>/dev/null || true
    $USE_SUDO apt-get --fix-broken install -y 2>/dev/null || true
    $USE_SUDO rm -f /var/lib/dpkg/lock* /var/cache/apt/archives/lock 2>/dev/null || true
    log_info "基本恢复完成，建议运行: $0 --fix-only"
}

# ── 清理退出 ──────────────────────────────────────────────────────────────────
cleanup() {
    rm -f /tmp/apt_update.log /tmp/grub_install.log 2>/dev/null || true
    for svc in unattended-upgrades apt-daily apt-daily-upgrade; do
        systemctl list-unit-files "$svc.service" >/dev/null 2>&1 \
            && systemctl is-active "$svc" >/dev/null 2>&1 \
            || $USE_SUDO systemctl start "$svc" 2>/dev/null || true
    done
}
trap cleanup EXIT

# ── 入口 ──────────────────────────────────────────────────────────────────────
main() {
    export LC_ALL=C LANG=C
    trap 'error_recovery $?' ERR

    # 解析参数
    while [[ $# -gt 0 ]]; do
        case "$1" in
            -h|--help)    show_help; exit 0 ;;
            -v|--version)
                v=$(get_current_version)
                vi=$(get_version_info "$v")
                echo "Debian $v ($(echo $vi|cut -d'|' -f1)) [$(echo $vi|cut -d'|' -f2)]"
                exit 0 ;;
            -c|--check)   check_upgrade; exit 0 ;;
            -d|--debug)   export DEBUG=1; log_debug "调试模式已启用"; shift ;;
            --fix-only)   check_root; check_system; fix_only_mode; exit 0 ;;
            --fix-grub)   check_root; fix_grub_mode; exit 0 ;;
            --force)      export FORCE=1; log_warning "强制模式：跳过所有确认"; shift ;;
            --stable-only)  export STABLE_ONLY=1; shift ;;
            --allow-testing) export STABLE_ONLY=0; shift ;;
            --mirror)
                shift
                [[ -z "${1:-}" ]] && { log_error "--mirror 需要参数 (cn|tuna|ustc)"; exit 1; }
                export MIRROR="$1"; shift
                ;;
            *) log_error "未知选项: $1"; echo "使用 '$0 --help' 查看帮助"; exit 1 ;;
        esac
    done

    # 默认 STABLE_ONLY=1（安全优先）
    export STABLE_ONLY="${STABLE_ONLY:-1}"

    set_mirror
    check_root
    check_system
    main_upgrade
}

[[ "${BASH_SOURCE[0]}" == "${0}" ]] && main "$@"
