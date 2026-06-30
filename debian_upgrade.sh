#!/bin/bash
# =============================================================================
# 脚本名称: debian_upgrade.sh
# 描    述: Debian 系统自动逐级升级脚本
#           生产入口支持 Debian 11~13，自动检测版本并升级到下一稳定版本
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
#   v3.1  2026-06-01  修复 Debian 12 已是最新稳定版时提示信息不显示的 bug
#                     - main_upgrade() 中提示逻辑判断取反导致提示从不显示
#                     - 更新 Debian 13 (Trixie) 状态标注为 testing/freeze
#                     - 更新 --help 中升级路径说明
#   v3.2  2026-06-01  更新 Debian 13 (Trixie) 为当前正式稳定版（2025-08-09 发布）
#                     - get_version_info: Trixie 状态从 testing/freeze 改为 stable
#                     - get_next_version: Debian 12 → 13 不再需要 --allow-testing
#                     - get_next_version: Debian 13 → 14 需要 --allow-testing（forky 为 unstable）
#                     - 最新点版本 13.5（2026-05-16），支持周期至 2030 年
#                     - 更新 --help 升级路径说明
#   v3.3  2026-06-09  安全加固：等待 APT 锁正常释放；支持 .sources；取消默认改网卡、重启网络、写 MBR 和 autoremove；补充测试、CI 与开发文档
#   v3.3.1 2026-06-09 新增 --preflight 深度检查（initramfs 预检、LD_PRELOAD 注入检测、失败诊断），优化升级后 initramfs 去重
#   v3.4  2026-06-10  代码审查与优化
#                     - 修复 dpkg --audit / --configure -a 可能触发 ERR 陷阱导致脚本中断的问题
#                     - 修复 fix_grub_mode() 中 lsblk 磁盘列表 awk 引用空字段的显示缺陷
#                     - 修复 get_current_version 策略4 缺少 forky 代号检测
#                     - 注释全面中文化，统一术语和表述
#   v3.4.1 2026-06-10  紧急修复：跨版本升级 GPG 签名验证失败
#                     - 切换软件源之前更新 debian-archive-keyring，确保包含目标版本的 GPG 密钥
#                     - apt-get update 遇到 NO_PUBKEY 错误时，临时使用 [trusted=yes] 安装密钥环后恢复验证
#   v3.4.2 2026-06-10  修复：云镜像 / 容器环境下 initramfs 预检因缺少 /var/tmp 失败
#                     - mkinitramfs 内部 mktemp 依赖 /var/tmp，部分云镜像未预置该目录
#                     - check_initramfs_health() 调用前确保 /var/tmp 存在
#   v3.5  2026-06-10  新增：升级后系统清理模式 --cleanup
#                     - 五步清理：废弃包/孤立依赖 → rc 残留配置 → 旧内核 → APT 缓存 → 旧 dpkg 配置
#                     - 清理前后显示磁盘用量对比，操作安全可重复执行
#   v3.6  2026-06-10  VPS 兼容性全面加固
#                     - ARM64 (aarch64) 架构支持：fix_grub_mode 自动检测 uname -m
#                     - 容器环境检测 (OpenVZ/LXC/Docker)：自动跳过 GRUB 和 /boot 相关操作
#                     - 非交互终端安全降级：缺失 /dev/tty 时不再崩溃（cron/systemd 环境）
#                     - EFI 目录多策略检测：findmnt → 常见路径 → /etc/fstab
#                     - 网络检测 HTTP 回退：ICMP 被阻断时尝试 wget/curl 检查镜像源
#                     - self-update CDN 回退：GitHub 不可达时自动尝试 jsDelivr CDN
#                     - GPG→404 错误分支顺序修复：两种错误同时出现时恢复路径可达
#                     - 日志文件拆分：apt-upgrade / dist-upgrade / initramfs 独立保存
#                     - 关联数组重构版本元数据：新增 Debian 版本只需追加三条记录
#                     - fix_only_mode 添加 stop_apt_units 防止定时任务抢占锁
#                     - mirror 无效值主动警告、wget 缺失提示、blkid sudo 前缀等细节修复
# =============================================================================
# 使用方法:
#   chmod +x debian_upgrade.sh
#   sudo ./debian_upgrade.sh              # 正常升级（稳定版，默认）
#   sudo ./debian_upgrade.sh --allow-testing  # 允许升级到 Debian 14 Forky
#   sudo ./debian_upgrade.sh --check      # 检查升级状态
#   sudo ./debian_upgrade.sh --fix-grub   # 专门修复 GRUB
#   sudo ./debian_upgrade.sh --help       # 查看完整帮助
# =============================================================================
# 注意事项:
#   - 需要 root 或 sudo 权限
#   - VPS 用户请确保有 VNC/控制台访问，以防重启后 SSH 断开
#   - 升级前建议快照或备份重要数据
#   - Debian 13 (Trixie) 于 2025-08-09 正式发布为 stable，当前最新为 13.5
#   - Debian 12 (Bookworm) 已进入 oldstable，仍在安全支持期内
# =============================================================================

set -Ee -o pipefail

# ── 脚本元信息 ────────────────────────────────────────────────────────────────
SCRIPT_VERSION="3.6"
SCRIPT_NAME="debian_upgrade.sh"
SCRIPT_DATE="2026-06-10"
SCRIPT_REPO="https://raw.githubusercontent.com/everett7623/debian-auto-upgrade/main/debian_upgrade.sh"
# GitHub 在国内可能被阻断，提供 CDN 回退地址
SCRIPT_REPO_CDN="https://cdn.jsdelivr.net/gh/everett7623/debian-auto-upgrade@main/debian_upgrade.sh"
RUN_ID="$(date +%Y%m%d_%H%M%S)_$$"
RUN_DIR="${TMPDIR:-/tmp}/debian-auto-upgrade-${RUN_ID}"
APT_UPDATE_LOG="${RUN_DIR}/apt-update.log"
APT_UPGRADE_LOG="${RUN_DIR}/apt-upgrade.log"
APT_DIST_UPGRADE_LOG="${RUN_DIR}/apt-dist-upgrade.log"
INITRAMFS_POST_LOG="${RUN_DIR}/initramfs-post.log"
KEEP_RUN_DIR=0
STOPPED_APT_UNITS=()

# ── 颜色定义 ──────────────────────────────────────────────────────────────────
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
CYAN='\033[0;36m'
NC='\033[0m'

# ── 日志函数 ──────────────────────────────────────────────────────────────────
log_info()    { echo -e "${BLUE}[INFO]${NC}    $(date '+%H:%M:%S') - $1" >&2; }
log_success() { echo -e "${GREEN}[SUCCESS]${NC} $(date '+%H:%M:%S') - $1" >&2; }
log_warning() { echo -e "${YELLOW}[WARNING]${NC} $(date '+%H:%M:%S') - $1" >&2; }
log_error()   { echo -e "${RED}[ERROR]${NC}   $(date '+%H:%M:%S') - $1" >&2; }
log_debug()   {
    if [[ "${DEBUG:-0}" == "1" ]]; then
        echo -e "${PURPLE}[DEBUG]${NC}   $(date '+%H:%M:%S') - $1" >&2
    fi
}

# ── 全局变量 ──────────────────────────────────────────────────────────────────
USE_SUDO=""
MIRROR_BASE="http://deb.debian.org/debian"
MIRROR_SECURITY="http://deb.debian.org/debian-security"

# ── 安全交互输入（缺失 /dev/tty 时优雅降级，如 cron / systemd 自动化环境）──
# 用法: safe_read "提示文本" [默认值]
safe_read() {
    local prompt="$1"
    local default="${2:-}"
    # 优先使用 /dev/tty（SSH 会话），不存在则回退到 stdin/stdout
    if [[ -e /dev/tty ]]; then
        [[ ! -t 0 ]] && exec 0</dev/tty
        echo -n "$prompt" >/dev/tty
        read -r REPLY </dev/tty
    elif [[ -t 0 ]]; then
        echo -n "$prompt"
        read -r REPLY
    else
        # 完全无交互终端（cron / systemd），返回默认值
        log_warning "无交互终端，使用默认值: ${default:-无}"
        REPLY="$default"
    fi
}

# ── 用户交互确认 ──────────────────────────────────────────────────────────────
get_user_confirmation() {
    local prompt="$1"
    local response=""
    while true; do
        safe_read "$prompt"
        response="$REPLY"
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
            disk=$($USE_SUDO blkid -U "$uuid" 2>/dev/null | sed -E 's/p?[0-9]+$//')
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
            if [[ "${MIRROR:-default}" != "default" ]]; then
                log_warning "未知镜像参数 '${MIRROR}'，回退到 Debian 官方源（支持: cn|tuna|ustc）"
            else
                log_debug "使用 Debian 官方源"
            fi
            ;;
    esac
}

# ── 版本信息映射（关联数组，新增版本只需追加一条记录）─────────────────────
# 未来 Debian 15 发布时，只需添加 [15] 条目到以下三个数组中即可
declare -A DEBIAN_CODENAME=(
    [8]="jessie"    [9]="stretch"   [10]="buster"
    [11]="bullseye" [12]="bookworm" [13]="trixie"   [14]="forky"
)
declare -A DEBIAN_STATUS=(
    [8]="archived"      [9]="archived"      [10]="archived"
    [11]="oldoldstable" [12]="oldstable"    [13]="stable"       [14]="testing"
)
# 标准相邻升级路径（不含 STABLE_ONLY 门控逻辑）
declare -A DEBIAN_NEXT=(
    [8]="9"  [9]="10"  [10]="11"  [11]="12"  [12]="13"
)

# ── Ubuntu LTS 版本映射 ──────────────────────────────────────────────────────
declare -A UBUNTU_CODENAME=(
    [20.04]="focal" [22.04]="jammy" [24.04]="noble" [26.04]="plucky"
)
declare -A UBUNTU_STATUS=(
    [20.04]="oldlts" [22.04]="oldlts" [24.04]="lts" [26.04]="lts"
)
declare -A UBUNTU_NEXT=(
    [20.04]="22.04" [22.04]="24.04" [24.04]="26.04"
)

get_os_id() {
    grep "^ID=" /etc/os-release 2>/dev/null | cut -d'=' -f2 | tr -d '"'
}

get_version_info() {
    local version="$1"
    local os_id="${2:-$(get_os_id)}"
    local codename status

    if [[ "$os_id" == "ubuntu" ]]; then
        codename="${UBUNTU_CODENAME[$version]:-unknown}"
        status="${UBUNTU_STATUS[$version]:-unsupported}"
        echo "${codename}|${status}"
        return
    fi

    codename="${DEBIAN_CODENAME[$version]:-unknown}"
    status="${DEBIAN_STATUS[$version]:-unknown}"
    echo "${codename}|${status}"
}

get_next_version() {
    local version="$1"
    local os_id="${2:-$(get_os_id)}"

    if [[ "$os_id" == "ubuntu" ]]; then
        echo "${UBUNTU_NEXT[$version]:-}"
        return
    fi

    local nxt="${DEBIAN_NEXT[$version]:-}"
    # Debian 13 → 14 受 STABLE_ONLY 门控（14 为 testing）
    if [[ "$version" == "13" ]]; then
        [[ "${STABLE_ONLY:-1}" == "1" ]] && echo "" || echo "14"
        return
    fi
    echo "$nxt"
}

# ── 当前版本检测（多策略，容错）──────────────────────────────────────────────
get_current_version() {
    local version_id=""
    local os_id
    os_id=$(get_os_id)

    log_debug "开始检测系统版本..."

    # Ubuntu 版本优先保留 major.minor（如 22.04）
    if [[ "$os_id" == "ubuntu" ]]; then
        if [[ -f /etc/os-release ]]; then
            version_id=$(grep "^VERSION_ID=" /etc/os-release \
                         | cut -d'"' -f2 | tr -d '[:space:]' 2>/dev/null || true)
            log_debug "ubuntu os-release VERSION_ID: '$version_id'"
        fi

        if [[ -z "$version_id" || ! "$version_id" =~ ^[0-9]+\.[0-9]+$ ]] \
           && command -v lsb_release >/dev/null 2>&1; then
            local uv
            uv=$(lsb_release -rs 2>/dev/null | tr -d '[:space:]')
            [[ "$uv" =~ ^[0-9]+\.[0-9]+$ ]] && version_id="$uv"
            log_debug "ubuntu lsb_release: '$uv'"
        fi

        if [[ -z "$version_id" || ! "$version_id" =~ ^[0-9]+\.[0-9]+$ ]]; then
            log_error "无法确定 Ubuntu 版本，调试信息："
            log_error "  os-release          : $(grep VERSION /etc/os-release 2>/dev/null || echo '不存在')"
            log_error "  内核版本            : $(uname -r)"
            echo ""
            return 1
        fi

        log_debug "最终版本: '$version_id'"
        echo "$version_id"
        return
    fi

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
        elif echo "$ap" | grep -q "forky";    then version_id="14"
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
    ip addr show  2>/dev/null | $USE_SUDO tee "$backup_dir/network/ip_addr_before.txt" >/dev/null || true
    ip route show 2>/dev/null | $USE_SUDO tee "$backup_dir/network/ip_route_before.txt" >/dev/null || true
    ip -o link show | awk -F': ' '{print $2}' | grep -v lo \
        | $USE_SUDO tee "$backup_dir/network/interface_names.txt" >/dev/null || true
    echo "$backup_dir"
}

# ── 网络配置修复 ──────────────────────────────────────────────────────────────
fix_network_config() {
    local backup_dir="$1"
    log_debug "核对网络接口（不会自动改名或重启网络服务）..."
    [[ -f "$backup_dir/network/interface_names.txt" ]] || return 0

    local old_if
    while read -r old_if; do
        [[ -z "$old_if" ]] && continue
        ip link show "$old_if" >/dev/null 2>&1 \
            || log_warning "升级前的网络接口 $old_if 当前不存在，请在控制台核对网络配置"
    done < "$backup_dir/network/interface_names.txt"
}

# ── 获取旧内核列表（共享函数，保留当前运行和最新安装的内核）──────────────────
# 输出空格分隔的旧内核包名，无旧内核时输出空字符串
get_old_kernels() {
    local cur_k latest_k
    cur_k=$(uname -r)
    latest_k=$(ls -t /boot/vmlinuz-* 2>/dev/null | head -1 | sed 's|/boot/vmlinuz-||')

    local result=""
    while read -r pkg; do
        local ver="${pkg#linux-image-}"
        # 兼容 linux-image-linux-image-* 双重前缀的包名
        ver="${ver#linux-image-}"
        if [[ "$ver" != "$cur_k" && "$ver" != "$latest_k" \
              && "$pkg" != "linux-image-amd64" \
              && "$pkg" != "linux-image-arm64" ]]; then
            result="$result $pkg"
        fi
    done < <(dpkg -l 'linux-image-*' 2>/dev/null | awk '/^ii/{print $2}')

    # 去除前导空格
    echo "${result# }"
}

# ── 清理旧内核（升级前 /boot 空间不足时调用）────────────────────────────────
clean_old_kernels() {
    log_info "清理旧内核以释放 /boot 空间..."
    local cur_k latest_k
    cur_k=$(uname -r)
    latest_k=$(ls -t /boot/vmlinuz-* 2>/dev/null | head -1 | sed 's|/boot/vmlinuz-||')
    log_info "当前内核: $cur_k | 最新内核: ${latest_k:-未知}"

    local to_remove
    to_remove=$(get_old_kernels)

    if [[ -n "$to_remove" ]]; then
        log_info "移除旧内核: $to_remove"
        # shellcheck disable=SC2086
        $USE_SUDO apt-get remove --purge -y $to_remove 2>/dev/null || true
        $USE_SUDO apt-get autoremove -y --purge 2>/dev/null || true
    else
        log_info "无需清理旧内核"
    fi

    $USE_SUDO find /boot \( -name "*.old" -o -name "*.bak" \) -delete 2>/dev/null || true

    if mount | grep -q " /boot "; then
        log_info "/boot 使用: $(df -h /boot | awk 'NR==2{print $5}') | 可用: $(df -h /boot | awk 'NR==2{print $4}')"
    fi
}

# ── 清理无效 / 过期 APT 源（升级前必须执行）──────────────────────────────────
# 解决问题：旧版本 backports、第三方源在升级后代号不匹配，导致 apt update 报 404
clean_apt_sources() {
    local target_codename="$1"
    log_info "备份并暂时禁用附加 APT 源（目标代号: $target_codename）..."

    if [[ -d /etc/apt/sources.list.d ]]; then
        local bak_dir="/etc/apt/sources.list.d.bak_$(date +%s)"
        $USE_SUDO cp -a /etc/apt/sources.list.d "$bak_dir"
        log_info "已备份 sources.list.d/ 到 $bak_dir"

        while read -r src_file; do
            [[ -z "$src_file" ]] && continue
            log_warning "暂时禁用附加源: $src_file"
            $USE_SUDO mv "$src_file" "${src_file}.disabled-by-debian-upgrade"
        done < <(find /etc/apt/sources.list.d/ -maxdepth 1 -type f \
            \( -name "*.list" -o -name "*.sources" \) 2>/dev/null)
    fi

    if [[ -f /etc/apt/sources.list ]]; then
        if grep -q "backports" /etc/apt/sources.list 2>/dev/null; then
            log_warning "注释掉 sources.list 中的 backports 行"
            $USE_SUDO sed -i '/^[[:space:]]*deb.*backports/s/^/# disabled by debian-auto-upgrade: /' \
                /etc/apt/sources.list
        fi
    fi

    log_success "附加 APT 源已备份并禁用；升级后请逐项检查再恢复"
}

# ── 系统环境检查 ──────────────────────────────────────────────────────────────
check_system() {
    log_info "检查系统环境..."

    local os_id
    os_id=$(grep "^ID=" /etc/os-release 2>/dev/null | cut -d'=' -f2 | tr -d '"')
    if [[ "$os_id" != "debian" && "$os_id" != "ubuntu" ]]; then
        log_error "此脚本仅适用于 Debian / Ubuntu 系统"
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
            log_warning "/boot 可用空间不足 200MB，请在升级前人工核对并清理旧内核"
        fi
    fi

    # 内存检查
    local avail_mem
    avail_mem=$(free -m | awk 'NR==2{print $7}')
    (( avail_mem < 256 )) && log_warning "可用内存不足 256MB，升级可能较慢"

    # 网络连通性（仅警告，不阻断）
    # ICMP 在某些 VPS 环境被阻断（特别是国内），优先用 HTTP 检测
    local os_id check_host check_url
    os_id=$(get_os_id)
    check_host="deb.debian.org"
    check_url="${MIRROR_BASE}"
    if [[ "$os_id" == "ubuntu" ]]; then
        check_host="archive.ubuntu.com"
        check_url="http://archive.ubuntu.com/ubuntu"
    fi

    local net_ok=0
    if ping -c 1 -W 5 "$check_host" >/dev/null 2>&1; then
        net_ok=1
    elif command -v wget >/dev/null 2>&1 && wget -q --timeout=10 --spider "${check_url}" 2>/dev/null; then
        net_ok=1
    elif command -v curl >/dev/null 2>&1 && curl -s --connect-timeout 10 --head "${check_url}" >/dev/null 2>&1; then
        net_ok=1
    fi
    (( net_ok )) || log_warning "无法连接 ${check_host}（ICMP + HTTP 均失败），请确认网络或使用 --mirror 选项"

    if is_container; then
        log_info "检测到容器环境（OpenVZ / LXC / Docker），跳过 /boot 和 GRUB 相关检查"
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

wait_for_apt_locks() {
    local timeout="${APT_LOCK_TIMEOUT:-300}"
    local waited=0
    local locks=(
        /var/lib/dpkg/lock-frontend
        /var/lib/dpkg/lock
        /var/cache/apt/archives/lock
        /var/lib/apt/lists/lock
    )

    command -v fuser >/dev/null 2>&1 || {
        log_warning "未安装 fuser，无法主动检查 APT 锁；继续前请确保没有其他包管理进程"
        return 0
    }

    while $USE_SUDO fuser "${locks[@]}" >/dev/null 2>&1; do
        if (( waited >= timeout )); then
            log_error "等待 APT/dpkg 锁超时（${timeout}s），请先结束正在运行的包管理任务"
            return 1
        fi
        (( waited % 15 == 0 )) && log_info "APT/dpkg 正忙，等待锁释放... (${waited}s/${timeout}s)"
        sleep 3
        ((waited += 3))
    done
}

check_runtime_injection() {
    local target dependency
    local suspicious=0

    for target in /sbin/fsck /sbin/fsck.ext4 /usr/sbin/fsck /usr/sbin/fsck.ext4; do
        [[ -x "$target" ]] || continue
        while read -r dependency; do
            case "$dependency" in
                /tmp/*|/var/tmp/*|/var/adm/*|/dev/shm/*|/home/*|/root/*)
                    log_error "检测到异常动态库依赖: $target -> $dependency"
                    suspicious=1
                    ;;
            esac
        done < <(
            env --unset=LD_PRELOAD ldd "$target" 2>/dev/null \
                | sed -nE 's/.*=>[[:space:]]+(\/[^[:space:]]+).*/\1/p; s/^[[:space:]]*(\/[^[:space:]]+).*/\1/p'
        )
    done

    if [[ -s /etc/ld.so.preload ]]; then
        log_warning "检测到非空 /etc/ld.so.preload，需确认其中库文件可信"
        while read -r dependency; do
            [[ -z "$dependency" || "$dependency" == \#* ]] && continue
            case "$dependency" in
                /lib/*|/lib64/*|/usr/lib/*|/usr/lib64/*) ;;
                *)
                    log_error "/etc/ld.so.preload 包含非常规路径: $dependency"
                    suspicious=1
                    ;;
            esac
        done < /etc/ld.so.preload
    fi

    if (( suspicious )); then
        log_error "系统可能存在异常 LD_PRELOAD 注入，已停止升级以避免将异常库写入 initramfs"
        log_error "请检查: cat /etc/ld.so.preload; env --unset=LD_PRELOAD ldd /sbin/fsck"
        return 1
    fi
}

check_initramfs_health() {
    command -v mkinitramfs >/dev/null 2>&1 || {
        log_warning "未找到 mkinitramfs，跳过 initramfs 预构建检查"
        return 0
    }

    local kernel
    kernel="$(uname -r)"
    [[ -d "/lib/modules/$kernel" ]] || {
        log_warning "缺少当前内核模块目录 /lib/modules/$kernel，跳过 initramfs 预构建检查"
        return 0
    }

    mkdir -p "$RUN_DIR"
    # mkinitramfs 内部 mktemp 依赖 /var/tmp，部分云镜像未预置该目录
    $USE_SUDO mkdir -p /var/tmp 2>/dev/null || true
    log_info "预检 initramfs 生成能力（内核: $kernel）..."
    if ! $USE_SUDO mkinitramfs -o "$RUN_DIR/initramfs-preflight.img" "$kernel" \
        >"$RUN_DIR/initramfs-preflight.log" 2>&1; then
        KEEP_RUN_DIR=1
        log_error "initramfs 预检失败，尚未切换软件源，已安全停止"
        if grep -q '/var/adm/\|LD_PRELOAD\|hooks/fsck failed' "$RUN_DIR/initramfs-preflight.log"; then
            log_error "检测到 fsck hook 或异常动态库路径问题，请先排查系统完整性"
        fi
        tail -n 20 "$RUN_DIR/initramfs-preflight.log" >&2
        return 1
    fi
    $USE_SUDO rm -f "$RUN_DIR/initramfs-preflight.img"
    log_success "initramfs 预检通过"
}

diagnose_upgrade_failure() {
    local log_file="$1"
    [[ -f "$log_file" ]] || return 0
    KEEP_RUN_DIR=1

    if grep -q 'hooks/fsck failed\|mkinitramfs_.*\/var\/adm\/' "$log_file"; then
        log_error "失败来自 initramfs fsck hook，不是网络或 APT 下载速度问题"
        log_error "若日志含 /var/adm/<UUID>，优先检查 /etc/ld.so.preload 和异常动态库注入"
        log_error "诊断命令: cat /etc/ld.so.preload; env --unset=LD_PRELOAD ldd /sbin/fsck"
    elif grep -q 'No space left on device' "$log_file"; then
        log_error "磁盘空间不足，请检查: df -h / /boot /var"
    elif grep -q 'Temporary failure resolving\|Could not resolve\|Connection timed out' "$log_file"; then
        log_error "检测到 DNS 或网络连接问题，请检查网络或使用 --mirror"
    elif grep -q 'dpkg was interrupted' "$log_file"; then
        log_error "dpkg 状态中断，请在确认系统安全后运行: dpkg --configure -a"
    fi

    log_error "完整日志保留于: $log_file"
}

stop_apt_units() {
    command -v systemctl >/dev/null 2>&1 || return 0
    local unit
    for unit in apt-daily.timer apt-daily-upgrade.timer apt-daily.service \
        apt-daily-upgrade.service unattended-upgrades.service; do
        if systemctl is-active --quiet "$unit"; then
            $USE_SUDO systemctl stop "$unit"
            STOPPED_APT_UNITS+=("$unit")
        fi
    done
}

# ── 升级前准备 ────────────────────────────────────────────────────────────────
pre_upgrade_preparation() {
    local target_codename="$1"
    log_info "执行升级前准备工作..."

    stop_apt_units
    wait_for_apt_locks
    check_runtime_injection
    check_initramfs_health

    # 修复 dpkg / 损坏依赖
    $USE_SUDO dpkg --audit 2>/dev/null || true
    $USE_SUDO dpkg --configure -a 2>/dev/null || true
    DEBIAN_FRONTEND=noninteractive $USE_SUDO apt-get --fix-broken install -y 2>/dev/null || true

    # 关键步骤：更新归档密钥环，确保包含目标版本的 GPG 签名密钥
    # 必须先更新当前源的密钥环，再切换到新版本源，否则 apt-get update 会报 NO_PUBKEY
    log_info "更新 Debian 归档密钥环..."
    $USE_SUDO apt-get update 2>/dev/null || log_warning "当前源更新失败，跳过密钥环更新"
    DEBIAN_FRONTEND=noninteractive $USE_SUDO apt-get install -y --reinstall debian-archive-keyring 2>/dev/null || true

    # 清理旧/无效 sources，避免 404
    clean_apt_sources "$target_codename"

    # 检查并预设 GRUB 磁盘，避免升级时弹出交互提示
    # 容器环境无需 GRUB，直接跳过
    if is_container; then
        log_info "检测到容器环境，跳过 GRUB 磁盘检测和预设"
    else
        local boot_mode boot_disk
        boot_mode=$(detect_boot_mode)
        boot_disk=$(detect_boot_disk)

        if [[ -z "$boot_disk" ]]; then
            log_warning "未自动检测到引导磁盘，升级后可能需手动修复 GRUB"
            if [[ "${FORCE:-0}" != "1" ]]; then
                if [[ -e /dev/tty ]]; then
                    read -p "是否继续升级？[y/N]: " -n 1 -r </dev/tty; echo
                else
                    log_warning "无交互终端，默认取消升级（使用 --force 跳过确认）"
                    REPLY=""
                fi
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
    fi

    log_success "升级前准备完成"
}

# ── 升级后修复 ────────────────────────────────────────────────────────────────
post_upgrade_fixes() {
    local backup_dir="$1"
    log_info "执行升级后修复..."

    fix_network_config "$backup_dir"

    # APT 的内核触发器通常已经生成 initramfs；仅在最新内核缺失时补建。
    local latest_kernel=""
    latest_kernel=$(ls -t /boot/vmlinuz-* 2>/dev/null | head -1 | sed 's|/boot/vmlinuz-||')
    if [[ -n "$latest_kernel" ]]; then
        if [[ -s "/boot/initrd.img-$latest_kernel" ]]; then
            log_info "最新内核 initramfs 已存在，跳过重复重建: $latest_kernel"
        else
            log_warning "最新内核缺少 initramfs，开始补建: $latest_kernel"
            if ! $USE_SUDO update-initramfs -c -k "$latest_kernel" 2>&1 \
                | tee "$INITRAMFS_POST_LOG"; then
                diagnose_upgrade_failure "$INITRAMFS_POST_LOG"
                return 1
            fi
        fi
    fi

    # 发行版升级不应无条件重装引导器或写入 MBR，仅刷新配置。
    # 容器环境无需 GRUB 操作
    if is_container; then
        log_info "容器环境，跳过 GRUB 配置刷新"
    elif command -v update-grub >/dev/null 2>&1; then
        log_info "刷新 GRUB 配置（不写入磁盘引导区）"
        $USE_SUDO update-grub || log_warning "GRUB 配置刷新失败，可稍后显式运行 --fix-grub"
    fi

    # 保留自动安装的包，避免在刚完成升级时误删仍需人工核对的依赖。
    log_info "跳过自动 autoremove；确认服务正常后可手动执行 apt-get autoremove --purge"
    $USE_SUDO apt-get autoclean 2>/dev/null || true

    sync
    log_success "升级后修复完成"
}

# ── 安全重启 ──────────────────────────────────────────────────────────────────
safe_reboot() {
    echo
    echo "╔════════════════════════════════════════╗"
    echo "║           ⚠️  即将重启系统              ║"
    echo "╚════════════════════════════════════════╝"
    if [[ -e /dev/tty ]]; then
        read -p "最后确认：确定要重启吗？[y/N]: " -n 1 -r </dev/tty; echo
    else
        log_warning "无交互终端，默认取消重启"
        REPLY=""
    fi
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
        $USE_SUDO systemctl reboot
    else
        $USE_SUDO reboot
    fi
}

# ── 帮助信息 ──────────────────────────────────────────────────────────────────
show_help() {
    cat << EOF
╔══════════════════════════════════════════════════════════════════╗
║     Debian / Ubuntu 自动逐级升级脚本 v${SCRIPT_VERSION} (${SCRIPT_DATE})      ║
╚══════════════════════════════════════════════════════════════════╝

📖 用法: $0 [选项]

🔧 选项:
  -h, --help            显示此帮助
    -v, --version         显示当前系统版本（Debian/Ubuntu）
  -c, --check           检查是否有可用升级
  --preflight           执行升级前深度检查，不切换软件源
  -d, --debug           启用调试模式
  --fix-only            仅修复系统，不升级
  --fix-grub            专门修复 GRUB 引导
  --cleanup             清理升级后的系统垃圾（旧内核、废弃包、残留配置）
  --self-update         从 GitHub 下载最新版本替换当前脚本
  --force               跳过所有确认提示
    --stable-only         仅升级到稳定版（Debian 默认，跳过 testing）
    --allow-testing       允许升级到 Debian 14 Forky（testing，仅 Debian）
  --mirror <cn|tuna|ustc>  使用国内镜像源

✨ 功能特性:
    ✅ 自动检测并逐级升级 Debian 11 → 12 → 13
    ✅ 支持 Ubuntu LTS 相邻升级：20.04 → 22.04 → 24.04 → 26.04
  ✅ 升级前备份并禁用 backports / 第三方源
  ✅ 兼容 UEFI / BIOS，支持 NVMe、virtio、xen 磁盘
  ✅ 备份并核对网络接口，不自动改名或重启网络
  ✅ /boot 空间不足时自动清理旧内核
  ✅ 默认只刷新 GRUB 配置，不写入 MBR
  ✅ 国内镜像源一键切换

🔄 升级路径:
  Debian 11 (Bullseye) → 12 (Bookworm) → 13 (Trixie) [当前稳定版]
                         → 14 (Forky)    [testing，需 --allow-testing]
    Ubuntu 20.04 (Focal) → 22.04 (Jammy) → 24.04 (Noble) → 26.04 (Plucky)
  Debian 8-10 的历史脚本仅供迁移研究，不属于当前生产支持范围

💻 示例:
  $0                           # 自动升级到下一稳定版
  $0 --check                   # 检查升级状态
  $0 --preflight               # 检查 initramfs、动态库和 dpkg 状态
  $0 --mirror cn               # 使用阿里云源升级（推荐国内）
  $0 --stable-only             # 仅升级到稳定版（默认行为）
  $0 --allow-testing           # 升级到 Debian 14 Forky（testing）
  $0 --allow-testing --force   # 强制升级到 Forky，跳过确认
  $0 --fix-grub                # 修复引导问题
  $0 --cleanup                 # 清理升级后残留（旧内核、废弃包）
  $0 --self-update             # 自动更新到脚本最新版本
  $0 --debug                   # 调试模式

⚠️  注意:
  • VPS 用户请确保有 VNC / 控制台访问权限
  • 升级前请创建系统快照或数据备份
  • Debian 13 (Trixie) 为当前推荐稳定版，支持至 2030 年
  • Debian 14 (Forky) 处于 testing，不建议生产环境使用
    • Ubuntu 仅支持 LTS 相邻升级，不执行跨代跳级
EOF
}

# ── 运行统计获取（visitor-badge.laobi.icu）───────────────────────────────────
fetch_hit_stats() {
    local url="https://visitor-badge.laobi.icu/badge?page_id=everett7623.debian-auto-upgrade"
    local response total

    # 尝试 curl（优先）或 wget 获取 SVG badge 响应
    if command -v curl >/dev/null 2>&1; then
        response=$(curl -s --connect-timeout 3 --max-time 3 "$url" 2>/dev/null) || return 1
    elif command -v wget >/dev/null 2>&1; then
        response=$(wget -q --timeout=3 -O - "$url" 2>/dev/null) || return 1
    else
        return 1
    fi

    # 从 SVG badge 解析计数（visitor-badge 返回单个数字：总访问量）
    # SVG 中的 <text> 元素包含数字
    total=$(echo "$response" | grep -oP '<text[^>]*>\K\d+(?=</text>)' | tail -1)
    # 兼容性：某些版本的 grep 无 -P 选项，回退到 sed
    if [[ -z "$total" ]]; then
        total=$(echo "$response" | sed -n 's/.*<text[^>]*>\([0-9]\+\)<\/text>.*/\1/p' | tail -1)
    fi

    [[ -n "$total" ]] && echo "$total" || return 1
}

# ── 检查升级状态 ──────────────────────────────────────────────────────────────
check_upgrade() {
    local os_id
    os_id=$(get_os_id)
    if [[ "$os_id" == "ubuntu" ]]; then
        check_upgrade_ubuntu
        return
    fi

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
        if (( cur < 11 )); then
            echo "  状    态: 已归档，不属于统一主脚本的自动升级范围"
            echo "  提    示: 请阅读 scripts/README.md 和 Debian 官方 Release Notes"
        else
            echo "  状    态: ✅ 已是最新稳定版本"
            echo "  提    示: 可用 --allow-testing 升级到 Debian 14 (forky) [testing]"
        fi
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
    local _boot_disk
    _boot_disk=$(detect_boot_disk)
    echo "  引导磁盘: ${_boot_disk:-未检测到}"
    echo "  根分区:   $(df -h / | awk 'NR==2{printf "已用 %s，可用 %s", $3, $4}')"

    if mount | grep -q " /boot "; then
        echo "  /boot:    $(df -h /boot | awk 'NR==2{printf "已用 %s，可用 %s", $3, $4}')"
    fi

    echo "  内存:     $(free -h | awk 'NR==2{printf "已用 %s / 总计 %s", $3, $2}')"

    if ping -c 1 -W 5 deb.debian.org >/dev/null 2>&1; then
        echo "  网络:     ✅ 可连接 deb.debian.org"
    elif { command -v wget >/dev/null 2>&1 && wget -q --timeout=10 --spider "${MIRROR_BASE}" 2>/dev/null; } \
      || { command -v curl >/dev/null 2>&1 && curl -s --connect-timeout 10 --head "${MIRROR_BASE}" >/dev/null 2>&1; }; then
        echo "  网络:     ⚡ ICMP 不可达但 HTTP 可达（可能被阻断 ICMP）"
    else
        echo "  网络:     ⚠️  无法连接 deb.debian.org（ICMP + HTTP 均失败）"
    fi

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
            echo "  ✅ 推荐升级到 Debian $nxt ($adv_name) - 当前稳定版"
            echo "  🔧 升级前建议先修复引导: $0 --fix-grub"
            echo "  🚀 执行升级:             $0"
        elif [[ "$adv_stat" == "oldstable" || "$adv_stat" == "oldoldstable" ]]; then
            echo "  ✅ 可升级到 Debian $nxt ($adv_name) - 旧稳定版（$adv_stat）"
            echo "  💡 建议升级完成后继续运行脚本再升一级到当前稳定版"
            echo "  🚀 执行升级: $0"
        elif [[ "$adv_stat" =~ testing ]]; then
            echo "  ⚠️  可升级到 Debian $nxt ($adv_name) - 测试版 (freeze 阶段)"
            echo "  🧪 测试环境升级: $0 --allow-testing"
            echo "  🛡️  保持稳定版本: $0 --stable-only  (推荐)"
        else
            echo "  ❌ 不建议升级到 Debian $nxt ($adv_name) - 当前状态为 $adv_stat"
        fi
    else
        echo "  ✅ 当前为最新稳定版 (Debian $cur)"
        echo "  🧪 如需升级到 Forky: $0 --allow-testing"
        echo "  🛡️  保持稳定版推荐:   $0 --stable-only (默认)"
    fi

    # 运行统计
    local _stats
    _stats=$(fetch_hit_stats 2>/dev/null) || _stats=""
    if [[ -n "$_stats" ]]; then
        echo "  📊 累计运行: ${_stats} 次"
    fi

    echo "═══════════════════════════════════════════"
}

check_upgrade_ubuntu() {
    local cur nxt cur_info nxt_info cur_name cur_stat nxt_name nxt_stat
    cur=$(get_current_version)
    cur_info=$(get_version_info "$cur" "ubuntu")
    cur_name=$(echo "$cur_info" | cut -d'|' -f1)
    cur_stat=$(echo "$cur_info" | cut -d'|' -f2)
    nxt=$(get_next_version "$cur" "ubuntu")

    echo "═══════════════════════════════════════════"
    echo "  🔍 Ubuntu LTS 升级状态检查"
    echo "═══════════════════════════════════════════"
    echo "  当前版本: Ubuntu $cur ($cur_name) [$cur_stat]"

    if [[ -z "$nxt" ]]; then
        echo "  状    态: ✅ 已是最新支持的 LTS 版本"
    else
        nxt_info=$(get_version_info "$nxt" "ubuntu")
        nxt_name=$(echo "$nxt_info" | cut -d'|' -f1)
        nxt_stat=$(echo "$nxt_info" | cut -d'|' -f2)
        echo "  可升级到: Ubuntu $nxt ($nxt_name) [$nxt_stat]"
    fi

    echo "───────────────────────────────────────────"
    echo "  启动模式: $(detect_boot_mode)"
    local _boot_disk
    _boot_disk=$(detect_boot_disk)
    echo "  引导磁盘: ${_boot_disk:-未检测到}"
    echo "  根分区:   $(df -h / | awk 'NR==2{printf "已用 %s，可用 %s", $3, $4}')"

    if mount | grep -q " /boot "; then
        echo "  /boot:    $(df -h /boot | awk 'NR==2{printf "已用 %s，可用 %s", $3, $4}')"
    fi

    echo "  内存:     $(free -h | awk 'NR==2{printf "已用 %s / 总计 %s", $3, $2}')"

    if ping -c 1 -W 5 archive.ubuntu.com >/dev/null 2>&1; then
        echo "  网络:     ✅ 可连接 archive.ubuntu.com"
    elif { command -v wget >/dev/null 2>&1 && wget -q --timeout=10 --spider "http://archive.ubuntu.com/ubuntu" 2>/dev/null; } \
      || { command -v curl >/dev/null 2>&1 && curl -s --connect-timeout 10 --head "http://archive.ubuntu.com/ubuntu" >/dev/null 2>&1; }; then
        echo "  网络:     ⚡ ICMP 不可达但 HTTP 可达（可能被阻断 ICMP）"
    else
        echo "  网络:     ⚠️  无法连接 archive.ubuntu.com（ICMP + HTTP 均失败）"
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
    if (( cur < 11 )); then
        log_error "Debian $cur 已进入归档范围，统一主脚本不再自动升级该版本"
        log_error "请阅读 scripts/README.md 和对应 Debian Release Notes，制定分阶段迁移方案"
        exit 1
    fi

    cur_info=$(get_version_info "$cur")
    cur_name=$(echo "$cur_info" | cut -d'|' -f1)
    cur_stat=$(echo "$cur_info" | cut -d'|' -f2)
    nxt=$(get_next_version "$cur")

    log_info "════════════════════════════════════════"
    log_info "Debian 自动升级脚本 v${SCRIPT_VERSION}"
    log_info "当前: Debian $cur ($cur_name) [$cur_stat]"

    # 运行统计
    local _stats
    _stats=$(fetch_hit_stats 2>/dev/null) || _stats=""
    if [[ -n "$_stats" ]]; then
        log_info "📊 累计运行: ${_stats} 次"
    fi

    if [[ -z "$nxt" ]]; then
        log_success "🎉 已是最新稳定版本 Debian $cur"
        log_info "提示: 可用 --allow-testing 升级到 Debian 14 (forky) [testing]"
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
            if [[ -e /dev/tty ]]; then
                read -p "确认升级到 Debian $nxt ($nxt_name)？[y/N]: " -n 1 -r </dev/tty; echo
            else
                log_warning "无交互终端，默认取消（使用 --force 跳过确认）"
                REPLY=""
            fi
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

deb ${MIRROR_SECURITY} ${nxt_name}${sec_suffix} main contrib non-free${nff}

deb ${MIRROR_BASE} ${nxt_name}-updates main contrib non-free${nff}
EOF

    log_success "软件源配置完成"

    # ── 步骤 2：更新包列表 ────────────────────────────────────────────────────
    log_info "步骤 2/4: 更新软件包列表"
    # 允许部分失败（如残留第三方源），继续升级
    mkdir -p "$RUN_DIR"
    $USE_SUDO apt-get -o Acquire::Languages=none update 2>&1 | tee "$APT_UPDATE_LOG" || {
        log_warning "apt-get update 出现错误（见上），检查是否可继续..."

        # GPG 签名验证错误优先处理 — 必须在 404 检查之前，否则同时存在两种错误时
        # GPG 恢复路径不可达（404 分支先匹配且重试失败后直接 exit）
        if grep -q "NO_PUBKEY\|GPG error\|is not signed" "$APT_UPDATE_LOG"; then
            log_warning "检测到 GPG 签名验证错误，尝试安装目标版本密钥环..."
            # 临时为所有源添加 [trusted=yes] 跳过签名验证
            $USE_SUDO sed -i 's/^deb /deb [trusted=yes] /' /etc/apt/sources.list
            $USE_SUDO apt-get -o Acquire::Languages=none update 2>/dev/null || {
                log_error "即使跳过签名验证，软件包列表更新仍然失败"
                $USE_SUDO sed -i 's/^deb \[trusted=yes\] /deb /' /etc/apt/sources.list
                exit 1
            }
            # 安装新版本的归档密钥环
            DEBIAN_FRONTEND=noninteractive $USE_SUDO apt-get install -y \
                debian-archive-keyring 2>/dev/null || true
            # 移除 [trusted=yes]，恢复正常的签名验证
            $USE_SUDO sed -i 's/^deb \[trusted=yes\] /deb /' /etc/apt/sources.list
            # 再次更新（可能仍有 404，继续处理）
            if $USE_SUDO apt-get -o Acquire::Languages=none update; then
                log_success "密钥环已更新，签名验证恢复正常"
            else
                log_warning "签名验证已恢复，但更新仍有错误（见上），尝试清理 404..."
                find /etc/apt/sources.list.d/ -maxdepth 1 -type f \
                    \( -name "*.list" -o -name "*.sources" \) 2>/dev/null \
                    | while read -r f; do
                        log_warning "  禁用: $f"
                        $USE_SUDO mv "$f" "${f}.disabled-by-debian-upgrade" 2>/dev/null || true
                    done
                $USE_SUDO apt-get -o Acquire::Languages=none update || {
                    log_error "软件包列表更新失败，请检查网络或手动修复源配置"
                    exit 1
                }
            fi
        # 如果是 Release 文件不存在（404），属于已清理源的残留，可忽略
        elif grep -q "404\|Release.*does not have" "$APT_UPDATE_LOG"; then
            log_warning "检测到 404 错误，尝试再次清理无效源后重试"
            # 禁用所有 sources.list.d 中的第三方源
            find /etc/apt/sources.list.d/ -maxdepth 1 -type f \
                \( -name "*.list" -o -name "*.sources" \) 2>/dev/null \
                | while read -r f; do
                    log_warning "  禁用: $f"
                    $USE_SUDO mv "$f" "${f}.disabled-by-debian-upgrade" 2>/dev/null || true
                done
            $USE_SUDO apt-get -o Acquire::Languages=none update || {
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
    if ! DEBIAN_FRONTEND=noninteractive $USE_SUDO apt-get upgrade -y \
        -o Dpkg::Options::="--force-confdef" \
        -o Dpkg::Options::="--force-confold" 2>&1 | tee "$APT_UPGRADE_LOG"; then
        log_error "最小升级失败，已停止；不会继续执行完整升级"
        diagnose_upgrade_failure "$APT_UPGRADE_LOG"
        exit 1
    fi

    log_info "  3.2 完整升级 (dist-upgrade)..."
    if ! DEBIAN_FRONTEND=noninteractive $USE_SUDO apt-get dist-upgrade -y \
        -o Dpkg::Options::="--force-confdef" \
        -o Dpkg::Options::="--force-confold" 2>&1 | tee "$APT_DIST_UPGRADE_LOG"; then
        log_error "完整升级失败，已停止自动重试，避免重复执行同一故障"
        diagnose_upgrade_failure "$APT_DIST_UPGRADE_LOG"
        exit 1
    fi

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
            local further_info
            further_info=$(get_version_info "$further")
            log_info "🚀 后续可继续升级到 Debian $further ($(echo $further_info | cut -d'|' -f1))"
        fi

        echo
        if [[ "${FORCE:-0}" != "1" ]]; then
            if [[ -e /dev/tty ]]; then
                read -p "是否需要 GRUB 修复？（通常无需）[y/N]: " -n 1 -r </dev/tty; echo
            else
                log_info "无交互终端，跳过 GRUB 修复询问"
                REPLY=""
            fi
            [[ $REPLY =~ ^[Yy]$ ]] && fix_grub_quick

            if [[ -e /dev/tty ]]; then
                read -p "是否现在重启系统？[y/N]: " -n 1 -r </dev/tty; echo
            else
                log_info "无交互终端，请稍后手动重启"
                REPLY=""
            fi
            [[ $REPLY =~ ^[Yy]$ ]] && safe_reboot \
                || log_info "请稍后手动重启: sudo reboot"
        fi
    else
        log_error "升级验证失败！期望: $nxt，检测到: $new_ver"
        log_error "请运行 $0 --fix-only 尝试修复"
        exit 1
    fi
}

# ── Ubuntu LTS 升级流程 ────────────────────────────────────────────────────────
ubuntu_upgrade() {
    local version_id
    version_id=$(grep "^VERSION_ID=" /etc/os-release 2>/dev/null | cut -d'"' -f2 | tr -d '[:space:]')

    # 验证是否为已知的 LTS 版本
    if [[ -z "${UBUNTU_CODENAME[$version_id]:-}" ]]; then
        log_error "不支持的 Ubuntu 版本: $version_id（仅支持 LTS: 20.04, 22.04, 24.04, 26.04）"
        exit 1
    fi

    local cur_codename="${UBUNTU_CODENAME[$version_id]}"
    local nxt_version="${UBUNTU_NEXT[$version_id]:-}"

    log_info "════════════════════════════════════════"
    log_info "Ubuntu LTS 升级脚本 v${SCRIPT_VERSION}"
    log_info "当前: Ubuntu $version_id ($cur_codename)"

    # 运行统计
    local _stats
    _stats=$(fetch_hit_stats 2>/dev/null) || _stats=""
    if [[ -n "$_stats" ]]; then
        log_info "📊 累计运行: ${_stats} 次"
    fi

    if [[ -z "$nxt_version" ]]; then
        log_success "🎉 已是最新支持的 LTS 版本 Ubuntu $version_id ($cur_codename)"
        exit 0
    fi

    local nxt_codename="${UBUNTU_CODENAME[$nxt_version]}"
    log_info "目标: Ubuntu $nxt_version ($nxt_codename)"

    # 用户确认
    if [[ "${FORCE:-0}" != "1" ]]; then
        if [[ -e /dev/tty ]]; then
            read -p "确认升级到 Ubuntu $nxt_version ($nxt_codename)？[y/N]: " -n 1 -r </dev/tty; echo
        else
            log_warning "无交互终端，默认取消（使用 --force 跳过确认）"
            REPLY=""
        fi
        [[ ! $REPLY =~ ^[Yy]$ ]] && { log_info "已取消"; exit 0; }
    fi

    # 升级前准备：锁等待、预检、依赖修复、禁用附加源
    local backup_dir
    backup_dir=$(save_network_config)
    stop_apt_units
    wait_for_apt_locks
    check_runtime_injection
    check_initramfs_health
    $USE_SUDO dpkg --audit 2>/dev/null || true
    $USE_SUDO dpkg --configure -a 2>/dev/null || true
    DEBIAN_FRONTEND=noninteractive $USE_SUDO apt-get --fix-broken install -y 2>/dev/null || true
    clean_apt_sources "$nxt_codename"

    # 确定 Ubuntu 镜像源
    local ubuntu_mirror="http://archive.ubuntu.com/ubuntu"
    local ubuntu_security="http://security.ubuntu.com/ubuntu"
    case "${MIRROR:-default}" in
        cn|china)
            ubuntu_mirror="http://mirrors.aliyun.com/ubuntu"
            ubuntu_security="http://mirrors.aliyun.com/ubuntu"
            ;;
        tuna)
            ubuntu_mirror="http://mirrors.tuna.tsinghua.edu.cn/ubuntu"
            ubuntu_security="http://mirrors.tuna.tsinghua.edu.cn/ubuntu"
            ;;
        ustc)
            ubuntu_mirror="http://mirrors.ustc.edu.cn/ubuntu"
            ubuntu_security="http://mirrors.ustc.edu.cn/ubuntu"
            ;;
    esac

    # ── 步骤 1: 备份并替换 sources.list ──────────────────────────────────────
    log_info "步骤 1/4: 更新软件源配置 → $nxt_codename"
    $USE_SUDO cp /etc/apt/sources.list \
        "/etc/apt/sources.list.backup.$(date +%s)" 2>/dev/null || true

    $USE_SUDO tee /etc/apt/sources.list > /dev/null << EOF
# Ubuntu $nxt_version ($nxt_codename) - 由 $SCRIPT_NAME v$SCRIPT_VERSION 自动生成
deb ${ubuntu_mirror} ${nxt_codename} main restricted universe multiverse
deb ${ubuntu_mirror} ${nxt_codename}-updates main restricted universe multiverse
deb ${ubuntu_security} ${nxt_codename}-security main restricted universe multiverse
EOF

    log_success "软件源配置完成"

    # ── 步骤 2: 更新包列表 ────────────────────────────────────────────────────
    log_info "步骤 2/4: 更新软件包列表"
    mkdir -p "$RUN_DIR"
    if ! $USE_SUDO apt-get -o Acquire::Languages=none update 2>&1 | tee "$APT_UPDATE_LOG"; then
        log_error "软件包列表更新失败，请检查网络或镜像源配置"
        exit 1
    fi

    # ── 步骤 3: 执行升级 ──────────────────────────────────────────────────────
    log_info "步骤 3/4: 执行系统升级"

    log_info "  3.1 最小升级 (upgrade)..."
    if ! DEBIAN_FRONTEND=noninteractive $USE_SUDO apt-get upgrade -y \
        -o Dpkg::Options::="--force-confdef" \
        -o Dpkg::Options::="--force-confold" 2>&1 | tee "$APT_UPGRADE_LOG"; then
        log_error "最小升级失败"
        diagnose_upgrade_failure "$APT_UPGRADE_LOG"
        exit 1
    fi

    log_info "  3.2 完整升级 (dist-upgrade)..."
    if ! DEBIAN_FRONTEND=noninteractive $USE_SUDO apt-get dist-upgrade -y \
        -o Dpkg::Options::="--force-confdef" \
        -o Dpkg::Options::="--force-confold" 2>&1 | tee "$APT_DIST_UPGRADE_LOG"; then
        log_error "完整升级失败"
        diagnose_upgrade_failure "$APT_DIST_UPGRADE_LOG"
        exit 1
    fi

    # ── 步骤 4: 验证升级结果 ──────────────────────────────────────────────────
    log_info "步骤 4/4: 验证升级结果"
    sleep 2
    local new_ver
    new_ver=$(grep "^VERSION_ID=" /etc/os-release 2>/dev/null | cut -d'"' -f2 | tr -d '[:space:]')

    if [[ "$new_ver" == "$nxt_version" ]]; then
        echo
        log_success "╔════════════════════════════════════════╗"
        log_success "║  🎉 升级完成！Ubuntu $version_id → $nxt_version ($nxt_codename)  ║"
        log_success "╚════════════════════════════════════════╝"
        echo
        log_info "📋 配置备份: $backup_dir"

        # 检查是否还有后续版本
        local further="${UBUNTU_NEXT[$nxt_version]:-}"
        if [[ -n "$further" ]]; then
            log_info "🚀 后续可继续升级到 Ubuntu $further (${UBUNTU_CODENAME[$further]})"
        fi

        echo
        if [[ "${FORCE:-0}" != "1" ]]; then
            if [[ -e /dev/tty ]]; then
                read -p "是否现在重启系统？[y/N]: " -n 1 -r </dev/tty; echo
            else
                log_info "无交互终端，请稍后手动重启"
                REPLY=""
            fi
            [[ $REPLY =~ ^[Yy]$ ]] && safe_reboot \
                || log_info "请稍后手动重启: sudo reboot"
        fi
    else
        log_error "升级验证失败！期望: $nxt_version，检测到: $new_ver"
        log_error "请检查系统状态并手动确认"
        exit 1
    fi
}

# ── 快速 GRUB 修复 ────────────────────────────────────────────────────────────
fix_grub_quick() {
    if is_container; then
        log_info "容器环境，跳过 GRUB 修复"
        return 0
    fi
    log_info "执行保守 GRUB 修复..."
    $USE_SUDO update-grub 2>/dev/null \
        || $USE_SUDO grub-mkconfig -o /boot/grub/grub.cfg 2>/dev/null || true

    if [[ ! -f /boot/grub/grub.cfg ]]; then
        log_warning "GRUB 配置不存在；请确认引导磁盘后显式运行: $0 --fix-grub"
    fi

    sync; sync
    log_success "保守 GRUB 修复完成"
}

# ── 获取 GRUB 目标架构 ────────────────────────────────────────────────────────
# 根据 uname -m 返回 GRUB 安装目标和包名
get_grub_target() {
    local arch
    arch=$(uname -m)
    case "$arch" in
        x86_64|amd64)
            echo "x86_64-efi|i386-pc|grub-efi-amd64|grub-pc" ;;
        aarch64|arm64)
            echo "arm64-efi|arm64-efi|grub-efi-arm64|grub-efi-arm64" ;;
        armv7l|armhf)
            echo "arm-efi|arm-efi|grub-efi-arm|grub-efi-arm" ;;
        *)
            echo "x86_64-efi|i386-pc|grub-efi-amd64|grub-pc"
            log_warning "未知架构 $arch，回退为 x86_64" ;;
    esac
}

# ── 检测是否为容器环境（OpenVZ / LXC / Docker）────────────────────────────
is_container() {
    # systemd-detect-virt --container 是最可靠的方法
    if command -v systemd-detect-virt >/dev/null 2>&1; then
        systemd-detect-virt --container >/dev/null 2>&1 && return 0
    fi
    # 后备：检查常见容器标志
    [[ -f /.dockerenv ]] && return 0
    grep -qE 'docker|lxc|container' /proc/1/environ 2>/dev/null && return 0
    # OpenVZ/Virtuozzo: /proc/vz 或 /proc/bc 存在
    [[ -d /proc/vz || -d /proc/bc ]] && return 0
    return 1
}

# ── 获取 EFI 目录 ──────────────────────────────────────────────────────────────
get_efi_dir() {
    # 方式1: findmnt 查找 ESP 挂载点
    if command -v findmnt >/dev/null 2>&1; then
        local esp
        # 优先选择路径包含 efi/EFI 的 vfat 挂载点
        esp=$(findmnt -n -o TARGET -t vfat 2>/dev/null | grep -i "efi" | head -1)
        # 回退：取第一个 vfat 挂载（兼容只有单一 ESP 的系统）
        [[ -z "$esp" ]] && esp=$(findmnt -n -o TARGET -t vfat 2>/dev/null | head -1)
        [[ -n "$esp" ]] && echo "$esp" && return
    fi
    # 方式2: 检查常见路径
    for d in /boot/efi /efi /boot/EFI; do
        [[ -d "$d" ]] && echo "$d" && return
    done
    # 方式3: /etc/fstab 查找 vfat 挂载
    awk '$3=="vfat" && /\/boot|\/efi/{print $2}' /etc/fstab 2>/dev/null | head -1
}

# ── GRUB 专项修复模式 ─────────────────────────────────────────────────────────
fix_grub_mode() {
    log_info "═══════════════════════════════════════════"
    log_info "🔧 GRUB 引导修复模式"
    log_info "═══════════════════════════════════════════"

    # 容器环境跳过 GRUB 操作
    if is_container; then
        log_warning "检测到容器环境，无需 GRUB 引导修复"
        log_info "容器使用宿主内核引导，跳过所有 GRUB 步骤"
        return 0
    fi

    local boot_mode boot_disk grub_target
    boot_mode=$(detect_boot_mode)
    boot_disk=$(detect_boot_disk)

    log_info "启动模式: $boot_mode | 架构: $(uname -m) | 引导磁盘: ${boot_disk:-未检测到}"

    # 解析 GRUB 目标架构
    local grub_info efi_target bios_target efi_pkg bios_pkg
    grub_info=$(get_grub_target)
    efi_target=$(echo "$grub_info" | cut -d'|' -f1)
    bios_target=$(echo "$grub_info" | cut -d'|' -f2)
    efi_pkg=$(echo "$grub_info"    | cut -d'|' -f3)
    bios_pkg=$(echo "$grub_info"   | cut -d'|' -f4)

    if [[ -z "$boot_disk" ]]; then
        log_warning "未能自动检测引导磁盘，请手动选择："
        local disks=()
        while read -r line; do
            disks+=("$line")
            echo "  $((${#disks[@]})). /dev/$line"
        done < <(lsblk -d -n -o NAME,TYPE,SIZE | awk '$2=="disk"{print $1" - "$3}')

        if [[ -e /dev/tty ]]; then
            read -p "输入编号或回车跳过: " -r </dev/tty
        else
            log_warning "无交互终端，跳过磁盘选择"
            REPLY=""
        fi
        if [[ "$REPLY" =~ ^[0-9]+$ ]] && (( REPLY >= 1 && REPLY <= ${#disks[@]} )); then
            boot_disk="/dev/$(echo "${disks[$((REPLY-1))]}" | awk '{print $1}')"
            log_info "已选择: $boot_disk"
        fi
    fi

    # 重装 GRUB 包
    log_info "步骤 1: 重装 GRUB 包"
    if [[ "$boot_mode" == "uefi" ]]; then
        DEBIAN_FRONTEND=noninteractive $USE_SUDO apt-get install --reinstall -y \
            "$efi_pkg" "${efi_pkg}-bin" grub2-common efibootmgr 2>/dev/null || true
    else
        DEBIAN_FRONTEND=noninteractive $USE_SUDO apt-get install --reinstall -y \
            "$bios_pkg" "${bios_pkg}-bin" grub2-common 2>/dev/null || true
    fi

    # 生成 GRUB 配置
    log_info "步骤 2: 生成 GRUB 配置"
    $USE_SUDO grub-mkconfig -o /boot/grub/grub.cfg 2>/dev/null \
        || $USE_SUDO update-grub 2>/dev/null || true

    # 安装 GRUB 到磁盘
    if [[ -n "$boot_disk" ]]; then
        log_info "步骤 3: 安装 GRUB 到 $boot_disk"
        if [[ "$boot_mode" == "uefi" ]]; then
            local efi_dir
            efi_dir=$(get_efi_dir)
            [[ -z "$efi_dir" ]] && efi_dir="/boot/efi"
            log_info "EFI 目录: $efi_dir"
            $USE_SUDO grub-install --target="$efi_target" \
                --efi-directory="$efi_dir" \
                --bootloader-id=debian \
                --recheck --force 2>&1 | tail -3
        else
            $USE_SUDO grub-install --target="$bios_target" \
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

    log_info "1/6 停止 apt 系统定时器"
    stop_apt_units

    log_info "2/6 检查异常动态库注入"
    check_runtime_injection

    log_info "3/6 检查 initramfs 生成能力"
    check_initramfs_health

    log_info "4/6 等待 APT/dpkg 锁释放"
    wait_for_apt_locks

    log_info "5/6 修复 dpkg 和依赖状态"
    if ! $USE_SUDO dpkg --configure -a 2>&1 | tee "$APT_UPGRADE_LOG"; then
        diagnose_upgrade_failure "$APT_UPGRADE_LOG"
        return 1
    fi
    if ! DEBIAN_FRONTEND=noninteractive $USE_SUDO apt-get --fix-broken install -y \
        2>&1 | tee "$APT_UPGRADE_LOG"; then
        diagnose_upgrade_failure "$APT_UPGRADE_LOG"
        return 1
    fi

    log_info "6/6 刷新 GRUB 配置"
    fix_grub_quick

    log_success "系统修复完成"
    log_info "建议运行: $0 --check 查看升级状态"
}

# ── 升级后清理模式 ──────────────────────────────────────────────────────────────
cleanup_mode() {
    log_info "═══════════════════════════════════════════"
    log_info "🧹 升级后系统清理"
    log_info "═══════════════════════════════════════════"

    # 清理前磁盘用量
    local before
    before=$(df -h / | awk 'NR==2{printf "已用 %s / 总计 %s (%s)", $3, $2, $5}' 2>/dev/null)
    log_info "清理前根分区: $before"

    # 步骤 1: 清理废弃包和孤立依赖
    log_info "步骤 1/5: 清理废弃包和孤立依赖..."
    $USE_SUDO apt-get autoremove --purge -y 2>&1 | tail -5 || true

    # 步骤 2: 清理 rc 状态残留配置
    log_info "步骤 2/5: 清理已删除包的残留配置..."
    local rc_pkgs
    rc_pkgs=$($USE_SUDO dpkg --list 2>/dev/null | awk '/^rc/{print $2}')
    if [[ -n "$rc_pkgs" ]]; then
        log_info "发现 $(echo "$rc_pkgs" | wc -l) 个残留配置包"
        echo "$rc_pkgs" | xargs -r $USE_SUDO dpkg --purge 2>/dev/null || true
    else
        log_info "无残留配置包"
    fi

    # 步骤 3: 清理旧内核（保留当前和最新）
    log_info "步骤 3/5: 清理旧内核..."
    local old_kernels
    old_kernels=$(get_old_kernels)

    if [[ -n "$old_kernels" ]]; then
        local kernel_count
        kernel_count=$(echo "$old_kernels" | wc -w)
        log_info "移除 $kernel_count 个旧内核: $old_kernels"
        # shellcheck disable=SC2086
        $USE_SUDO apt-get remove --purge -y $old_kernels 2>/dev/null || true
    else
        log_info "无旧内核需清理"
    fi
    # 清理残留的 .old / .bak initramfs 文件
    $USE_SUDO find /boot \( -name "*.old" -o -name "*.bak" \) -delete 2>/dev/null || true

    # 步骤 4: 清理 APT 缓存
    log_info "步骤 4/5: 清理 APT 缓存..."
    $USE_SUDO apt-get autoclean 2>/dev/null || true
    $USE_SUDO apt-get clean 2>/dev/null || true

    # 步骤 5: 清理旧的 dpkg 配置文件
    log_info "步骤 5/5: 清理旧配置文件..."
    local old_configs
    old_configs=$($USE_SUDO find /etc -maxdepth 5 \
        \( -name "*.dpkg-old" -o -name "*.dpkg-dist" -o -name "*.dpkg-bak" \) \
        -type f 2>/dev/null)
    local config_count
    config_count=$(echo "$old_configs" | grep -c '.' 2>/dev/null || echo 0)
    if (( config_count > 0 )); then
        log_info "移除 $config_count 个旧配置文件:"
        echo "$old_configs" | while read -r f; do
            [[ -n "$f" ]] && log_debug "  移除: $f"
        done
        echo "$old_configs" | xargs -r $USE_SUDO rm -f 2>/dev/null || true
    else
        log_info "无旧配置文件需清理"
    fi

    # 清理后磁盘用量
    local after
    after=$(df -h / | awk 'NR==2{printf "已用 %s / 总计 %s (%s)", $3, $2, $5}' 2>/dev/null)
    log_info "清理后根分区: $after"

    log_success "═══════════════════════════════════════════"
    log_success "🎉 系统清理完成"
    log_success "═══════════════════════════════════════════"
}

# ── 脚本自更新 ──────────────────────────────────────────────────────────────────
self_update_mode() {
    local script_path
    script_path="$(realpath "$0")"
    if [[ ! -w "$script_path" ]]; then
        log_error "无写入权限: $script_path"
        log_error "请使用 root 或 sudo 运行: sudo $0 --self-update"
        return 1
    fi

    log_info "═══════════════════════════════════════════"
    log_info "🔄 检查并更新脚本"
    log_info "═══════════════════════════════════════════"

    local tmp_file
    tmp_file="$(mktemp)"
    log_info "当前版本: v${SCRIPT_VERSION}"

    if ! command -v wget >/dev/null 2>&1; then
        log_error "未找到 wget，请先安装: sudo apt-get install wget"
        log_error "也可使用 curl 手动下载: curl -fL --proto '=https' --tlsv1.2 -o debian_upgrade.sh $SCRIPT_REPO"
        rm -f "$tmp_file"
        return 1
    fi

    log_info "下载最新版本..."

    # 尝试主地址（GitHub），失败则使用 CDN 回退（国内网络更稳定）
    local download_url="$SCRIPT_REPO"
    if ! wget -q --timeout=15 -O "$tmp_file" "$download_url" 2>/dev/null; then
        log_warning "主地址下载失败，尝试 CDN 回退地址..."
        download_url="$SCRIPT_REPO_CDN"
        if ! wget -q --timeout=30 -O "$tmp_file" "$download_url" 2>/dev/null; then
            log_error "所有下载地址均失败，请检查网络或手动下载"
            log_error "  主地址: $SCRIPT_REPO"
            log_error "  CDN  :  $SCRIPT_REPO_CDN"
            rm -f "$tmp_file"
            return 1
        fi
    fi

    local remote_version
    remote_version=$(grep '^SCRIPT_VERSION=' "$tmp_file" | head -1 | cut -d'"' -f2)
    if [[ -z "$remote_version" ]]; then
        log_error "无法解析远程版本，请手动下载: $download_url"
        rm -f "$tmp_file"
        return 1
    fi

    log_info "远程版本: v${remote_version}"

    if [[ "$remote_version" == "$SCRIPT_VERSION" ]]; then
        log_success "已是最新版本 v${SCRIPT_VERSION}"
        rm -f "$tmp_file"
        return 0
    fi

    # 预检远程脚本语法
    if ! bash -n "$tmp_file" 2>/dev/null; then
        log_error "远程脚本语法检查失败，拒绝更新"
        rm -f "$tmp_file"
        return 1
    fi

    # 备份当前脚本
    local backup
    backup="$(dirname "$(realpath "$0")")/${SCRIPT_NAME}.v${SCRIPT_VERSION}.bak"
    cp "$(realpath "$0")" "$backup" 2>/dev/null || true
    log_info "已备份当前版本: $backup"

    # 替换并保持权限
    cat "$tmp_file" > "$(realpath "$0")"
    chmod +x "$(realpath "$0")"
    rm -f "$tmp_file"

    log_success "═══════════════════════════════════════════"
    log_success "🎉 更新完成: v${SCRIPT_VERSION} → v${remote_version}"
    log_success "═══════════════════════════════════════════"
    log_info "重新运行以使用新版本: $0 --help"
}

preflight_mode() {
    log_info "执行升级前深度检查（不会切换软件源或升级软件包）..."
    wait_for_apt_locks
    check_runtime_injection
    check_initramfs_health

    if $USE_SUDO dpkg --audit | grep -q .; then
        log_error "dpkg 检测到未完成配置的软件包，请先处理后再升级"
        $USE_SUDO dpkg --audit >&2
        return 1
    fi

    log_success "升级前深度检查通过"
}

# ── 错误恢复 ──────────────────────────────────────────────────────────────────
error_recovery() {
    trap - ERR
    local code="$1"
    KEEP_RUN_DIR=1
    log_error "脚本异常退出（退出码: $code）"
    log_info "已停止自动恢复，避免在根因未解决时重复执行耗时的包管理操作"
    log_info "请查看上方首个错误；确认系统安全后再运行: $0 --fix-only"
}

# ── 清理退出 ──────────────────────────────────────────────────────────────────
cleanup() {
    if [[ "$KEEP_RUN_DIR" == "1" ]]; then
        log_warning "诊断日志已保留: $RUN_DIR"
    else
        rm -rf "$RUN_DIR" 2>/dev/null || true
    fi
    local unit
    for unit in "${STOPPED_APT_UNITS[@]}"; do
        $USE_SUDO systemctl start "$unit" 2>/dev/null || true
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
                local os_id v vi
                os_id=$(get_os_id)
                v=$(get_current_version)
                vi=$(get_version_info "$v" "$os_id")
                if [[ "$os_id" == "ubuntu" ]]; then
                    echo "Ubuntu $v ($(echo "$vi"|cut -d'|' -f1)) [$(echo "$vi"|cut -d'|' -f2)]"
                else
                    echo "Debian $v ($(echo "$vi"|cut -d'|' -f1)) [$(echo "$vi"|cut -d'|' -f2)]"
                fi
                exit 0 ;;
            -c|--check)   check_upgrade; exit 0 ;;
            --preflight)  check_root; check_system; preflight_mode; exit 0 ;;
            --cleanup)    check_root; check_system; cleanup_mode; exit 0 ;;
            --self-update) self_update_mode; exit 0 ;;
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

    # OS 类型分流：Ubuntu 走 ubuntu_upgrade，Debian 走 main_upgrade
    local os_id
    os_id=$(grep "^ID=" /etc/os-release 2>/dev/null | cut -d'=' -f2 | tr -d '"')
    if [[ "$os_id" == "ubuntu" ]]; then
        ubuntu_upgrade
    else
        main_upgrade
    fi
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
