#!/bin/bash

# VPS-specific tests for debian_upgrade.sh
# Author: everett7623

set -e

# Test configuration
SCRIPT_PATH="../debian_upgrade.sh"
TEST_DIR="$(dirname "$0")"

# Colors
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Test counters
VPS_TESTS_RUN=0
VPS_TESTS_PASSED=0
VPS_TESTS_FAILED=0

# Logging functions
log_vps_test() {
    echo -e "${BLUE}[VPS-TEST]${NC} $1"
    VPS_TESTS_RUN=$((VPS_TESTS_RUN + 1))
}

log_vps_pass() {
    echo -e "${GREEN}[VPS-PASS]${NC} $1"
    VPS_TESTS_PASSED=$((VPS_TESTS_PASSED + 1))
}

log_vps_fail() {
    echo -e "${RED}[VPS-FAIL]${NC} $1"
    VPS_TESTS_FAILED=$((VPS_TESTS_FAILED + 1))
}

# Detect current VPS environment
detect_current_vps() {
    local vps_type="unknown"
    
    # Check for common VPS indicators
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
    elif command -v systemd-detect-virt >/dev/null 2>&1; then
        vps_type=$(systemd-detect-virt 2>/dev/null || echo "unknown")
    fi
    
    echo "$vps_type"
}

# Test VPS detection functionality
test_vps_detection() {
    log_vps_test "VPS environment detection"
    
    local detected_vps=$(detect_current_vps)
    
    if [[ "$detected_vps" != "unknown" ]]; then
        log_vps_pass "VPS environment detected: $detected_vps"
    else
        log_vps_pass "Physical machine or undetected VPS type"
    fi
}

# Test network connectivity in VPS environment
test_vps_network() {
    log_vps_test "VPS network connectivity"
    
    local test_hosts=("deb.debian.org" "security.debian.org" "8.8.8.8")
    local failed_hosts=()
    
    for host in "${test_hosts[@]}"; do
        if ! ping -c 1 -W 5 "$host" >/dev/null 2>&1; then
            failed_hosts+=("$host")
        fi
    done
    
    if [ ${#failed_hosts[@]} -eq 0 ]; then
        log_vps_pass "All network connectivity tests passed"
    else
        log_vps_fail "Failed to connect to: ${failed_hosts[*]}"
    fi
}

# Test DNS resolution in VPS
test_vps_dns() {
    log_vps_test "DNS resolution"
    
    local test_domains=("debian.org" "security.debian.org" "deb.debian.org")
    local dns_failures=()
    
    for domain in "${test_domains[@]}"; do
        if ! nslookup "$domain" >/dev/null 2>&1; then
            dns_failures+=("$domain")
        fi
    done
    
    if [ ${#dns_failures[@]} -eq 0 ]; then
        log_vps_pass "DNS resolution working correctly"
    else
        log_vps_fail "DNS resolution failed for: ${dns_failures[*]}"
    fi
}

# Test disk space requirements
test_vps_disk_space() {
    log_vps_test "Disk space requirements"
    
    local available_kb=$(df / | awk 'NR==2 {print $4}')
    local required_kb=$((2 * 1024 * 1024))  # 2GB in KB
    
    if [ "$available_kb" -gt "$required_kb" ]; then
        log_vps_pass "Sufficient disk space available ($(($available_kb / 1024 / 1024))GB)"
    else
        log_vps_fail "Insufficient disk space (need 2GB, have $(($available_kb / 1024 / 1024))GB)"
    fi
}

# Test memory requirements
test_vps_memory() {
    log_vps_test "Memory requirements"
    
    local available_mb=$(free -m | awk 'NR==2{printf "%.0f", $7}')
    local required_mb=512
    
    if [ "$available_mb" -gt "$required_mb" ]; then
        log_vps_pass "Sufficient memory available (${available_mb}MB)"
    else
        log_vps_fail "Low memory warning (${available_mb}MB available, ${required_mb}MB recommended)"
    fi
}

# Test VPS-specific file systems
test_vps_filesystem() {
    log_vps_test "VPS filesystem compatibility"
    
    local fs_type=$(df -T / | awk 'NR==2 {print $2}')
    local supported_fs=("ext4" "ext3" "xfs" "btrfs")
    
    if printf '%s\n' "${supported_fs[@]}" | grep -q "^${fs_type}$"; then
        log_vps_pass "Filesystem type supported: $fs_type"
    else
        log_vps_fail "Filesystem type may have issues: $fs_type"
    fi
}

# Test container-specific limitations
test_container_limitations() {
    log_vps_test "Container limitations check"
    
    local container_type=$(systemd-detect-virt 2>/dev/null || echo "none")
    
    case "$container_type" in
        "docker")
            if [[ -f /.dockerenv ]]; then
                log_vps_pass "Docker container detected - aware of limitations"
            else
                log_vps_fail "Docker detection inconsistency"
            fi
            ;;
        "lxc"|"lxc-libvirt")
            log_vps_pass "LXC container detected - checking capabilities"
            ;;
        "openvz")
            log_vps_pass "OpenVZ container detected - applying specific fixes"
            ;;
        "none"|"")
            log_vps_pass "No container limitations detected"
            ;;
        *)
            log_vps_pass "Container type: $container_type"
            ;;
    esac
}

# Test APT lock handling in VPS
test_apt_lock_handling() {
    log_vps_test "APT lock file handling"
    
    # Check if APT is currently locked
    if [[ -f /var/lib/dpkg/lock-frontend ]] || [[ -f /var/lib/apt/lists/lock ]]; then
        if timeout 10 sudo apt update -qq >/dev/null 2>&1; then
            log_vps_pass "APT operations working despite locks"
        else
            log_vps_fail "APT appears to be locked"
        fi
    else
        log_vps_pass "No APT locks detected"
    fi
}

# Test timezone configuration
test_timezone_config() {
    log_vps_test "Timezone configuration"
    
    if [[ -f /etc/timezone ]]; then
        local tz=$(cat /etc/timezone)
        log_vps_pass "Timezone configured: $tz"
    else
        log_vps_fail "Timezone not configured"
    fi
}

# Test locale configuration
test_locale_config() {
    log_vps_test "Locale configuration"
    
    if locale -a | grep -q "en_US.utf8\|C.UTF-8" 2>/dev/null; then
        log_vps_pass "Basic locales available"
    else
        log_vps_fail "Basic locales not configured"
    fi
}

# Test service management capabilities
test_service_management() {
    log_vps_test "Service management capabilities"
    
    local test_services=("ssh" "networking")
    local service_issues=()
    
    for service in "${test_services[@]}"; do
        if ! systemctl is-active "$service" >/dev/null 2>&1; then
            service_issues+=("$service")
        fi
    done
    
    if [ ${#service_issues[@]} -eq 0 ]; then
        log_vps_pass "Critical services are running"
    else
        log_vps_fail "Service issues detected: ${service_issues[*]}"
    fi
}

# Test script execution in VPS context
test_script_vps_execution() {
    log_vps_test "Script VPS-specific execution"
    
    # Test dry-run mode
    if timeout 60 bash "$SCRIPT_PATH" --check >/dev/null 2>&1; then
        log_vps_pass "Script executes correctly in VPS environment"
    else
        log_vps_fail "Script execution issues in VPS environment"
    fi
}

# Main VPS test runner
run_vps_tests() {
    echo "=========================================="
    echo "Debian Auto Upgrade - VPS Environment Tests"
    echo "=========================================="
    echo
    
    local detected_vps=$(detect_current_vps)
    echo "Current environment: $detected_vps"
    echo
    
    # Run VPS-specific tests
    test_vps_detection
    test_vps_network
    test_vps_dns
    test_vps_disk_space
    test_vps_memory
    test_vps_filesystem
    test_container_limitations
    test_apt_lock_handling
    test_timezone_config
    test_locale_config
    test_service_management
    test_script_vps_execution
    
    # Print VPS test results
    echo
    echo "=========================================="
    echo "VPS Test Results Summary"
    echo "=========================================="
    echo "VPS Tests Run: $VPS_TESTS_RUN"
    echo "VPS Tests Passed: $VPS_TESTS_PASSED"
    echo "VPS Tests Failed: $VPS_TESTS_FAILED"
    echo
    
    if [ $VPS_TESTS_FAILED -eq 0 ]; then
        echo -e "${GREEN}All VPS tests passed!${NC}"
        return 0
    else
        echo -e "${RED}Some VPS tests failed!${NC}"
        return 1
    fi
}

# Script entry point
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    run_vps_tests "$@"
fi
