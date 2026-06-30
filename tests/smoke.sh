#!/usr/bin/env bash
set -Eeuo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SCRIPT="${ROOT_DIR}/distro_upgrade.sh"

fail() {
    printf 'FAIL: %s\n' "$1" >&2
    exit 1
}

bash -n "$SCRIPT"

help_output="$(bash "$SCRIPT" --help)"
grep -q -- '--stable-only' <<<"$help_output" || fail "help misses --stable-only"
grep -q -- '--allow-testing' <<<"$help_output" || fail "help misses --allow-testing"
grep -q -- '--preflight' <<<"$help_output" || fail "help misses --preflight"
grep -q -- '--cleanup' <<<"$help_output" || fail "help misses --cleanup"
grep -q -- '--self-update' <<<"$help_output" || fail "help misses --self-update"
grep -q -- 'Ubuntu 20.04 (Focal)' <<<"$help_output" || fail "help misses Ubuntu LTS path"

# Source functions without executing main.
# shellcheck source=../distro_upgrade.sh
source "$SCRIPT"
trap - EXIT

[[ "$(get_next_version 11)" == "12" ]] || fail "Debian 11 target"
[[ "$(get_next_version 12)" == "13" ]] || fail "Debian 12 target"
[[ -z "$(STABLE_ONLY=1 get_next_version 13)" ]] || fail "stable policy"
[[ "$(STABLE_ONLY=0 get_next_version 13)" == "14" ]] || fail "testing policy"
[[ "$(get_version_info 13)" == "trixie|stable" ]] || fail "Trixie status"
[[ "$(get_version_info 14)" == "forky|testing" ]] || fail "Forky status"
[[ -z "$(STABLE_ONLY=1 get_next_version 14)" ]] || fail "Forky stable policy"
[[ -z "$(get_next_version 14)" ]] || fail "Forky no further upgrade"
[[ "$(get_version_info 22.04 ubuntu)" == "jammy|oldlts" ]] || fail "Ubuntu 22.04 status"
[[ "$(get_version_info 24.04 ubuntu)" == "noble|lts" ]] || fail "Ubuntu 24.04 status"
[[ "$(get_next_version 22.04 ubuntu)" == "24.04" ]] || fail "Ubuntu 22.04 target"
[[ -z "$(get_next_version 26.04 ubuntu)" ]] || fail "Ubuntu latest no further upgrade"

# Validate default distro-aware routing via get_os_id fallback (without passing explicit distro arg)
orig_get_os_id="$(declare -f get_os_id)"
eval "get_os_id() { echo ubuntu; }"
[[ "$(get_version_info 22.04)" == "jammy|oldlts" ]] || fail "Ubuntu default routing status"
[[ "$(get_next_version 24.04)" == "26.04" ]] || fail "Ubuntu default routing next"
eval "$orig_get_os_id"

# Debian path should have exactly 1 dist-upgrade; Ubuntu path adds another (total 2 is valid)
dist_upgrade_count="$(grep -c 'apt-get dist-upgrade' "$SCRIPT")"
[[ "$dist_upgrade_count" -le "2" ]] || fail "dist-upgrade should run at most once per upgrade path"

if grep -q '^deb-src ' "$SCRIPT"; then
    fail "generated sources should not download source indexes by default"
fi

grep -q 'check_initramfs_health' "$SCRIPT" || fail "missing initramfs preflight"
grep -q 'check_runtime_injection' "$SCRIPT" || fail "missing runtime injection check"
grep -q 'debian-archive-keyring' "$SCRIPT" || fail "missing keyring update before source switch"
grep -Fq '[trusted=yes]' "$SCRIPT" || fail "missing GPG error recovery path"

failure_log="$(mktemp)"
printf '%s\n' "E: /usr/share/initramfs-tools/hooks/fsck failed with return 1." >"$failure_log"
KEEP_RUN_DIR=0
diagnose_upgrade_failure "$failure_log" >/dev/null 2>&1
[[ "$KEEP_RUN_DIR" == "1" ]] || fail "failure diagnostics should preserve logs"
rm -f "$failure_log"

if grep -Eq 'rm[[:space:]]+-f[[:space:]]+/var/(lib/dpkg|cache/apt).*(lock|lock-frontend)' "$SCRIPT"; then
    fail "main script deletes package-manager locks"
fi

if grep -Eq 'dd[[:space:]].*of=.*boot_disk' "$SCRIPT"; then
    fail "main upgrade path contains direct boot-sector write"
fi

printf 'smoke tests passed\n'

# ═══════════════════════════════════════════════════════════════════════════════
# Bug Condition Exploration Tests
# These tests encode the EXPECTED correct behavior.
# On UNFIXED code, these tests FAIL (proving the bugs exist).
# After fixes are applied, they should PASS.
# ═══════════════════════════════════════════════════════════════════════════════

BUG_TESTS_PASSED=0
BUG_TESTS_FAILED=0
BUG_TESTS_ERRORS=""

bug_pass() {
    BUG_TESTS_PASSED=$((BUG_TESTS_PASSED + 1))
    printf '  ✅ PASS: %s\n' "$1"
}

bug_fail() {
    BUG_TESTS_FAILED=$((BUG_TESTS_FAILED + 1))
    BUG_TESTS_ERRORS="${BUG_TESTS_ERRORS}  FAIL: $1\n"
    printf '  ❌ FAIL: %s\n' "$1"
}

printf '\n══ Bug Condition Exploration Tests ══\n'

# ── Bug 1.1: cleanup_mode() awk string arithmetic ────────────────────────────
# The awk expression `($3/$2)*100` operates on df -h output with unit suffixes.
# When $3 and $2 have DIFFERENT unit prefixes (e.g., "512M" vs "20G"),
# awk strips trailing letters giving (512/20)*100 = 2560% instead of 3%.
# Expected fix: use $5 (Use%) field directly - it already has the correct %.
printf '\n─── Bug 1.1: awk 字符串算术 ───\n'

# Verify the script's cleanup_mode uses $5 (correct) instead of ($3/$2)*100 (buggy)
cleanup_body=$(sed -n '/^cleanup_mode()/,/^[a-zA-Z_]*() *{/p' "$SCRIPT")
has_buggy_awk=$(echo "$cleanup_body" | grep -c '(\$3/\$2)\*100' 2>/dev/null || true)
has_correct_awk=$(echo "$cleanup_body" | grep -c 'awk.*\$5' 2>/dev/null || true)
has_buggy_awk="${has_buggy_awk:-0}"
has_correct_awk="${has_correct_awk:-0}"

if [[ "$has_buggy_awk" == "0" ]] && [[ "$has_correct_awk" -gt "0" ]]; then
    bug_pass "Bug 1.1: cleanup_mode uses awk \$5 field (not buggy (\$3/\$2)*100 arithmetic)"
else
    bug_fail "Bug 1.1: cleanup_mode still uses (\$3/\$2)*100 arithmetic instead of \$5 field (buggy_count=$has_buggy_awk, correct_count=$has_correct_awk)"
fi

# ── Bug 1.2: bash reserved keyword 'fi' used as variable name ────────────────
# `local fi` conflicts with bash's `fi` keyword (if/fi pair).
# Expected fix: rename to 'further_info' or any non-reserved name.
printf '\n─── Bug 1.2: bash 关键字冲突 ───\n'

# Check if the script contains 'local fi' as a variable declaration
if grep -qE '^\s*local\s+fi\s*$' "$SCRIPT"; then
    bug_fail "Bug 1.2: script uses 'local fi' - reserved keyword conflict (should use 'further_info' or similar)"
else
    bug_pass "Bug 1.2: no reserved keyword used as variable name"
fi

# ── Bug 1.3: error_recovery ERR trap cascade recursion ───────────────────────
# In `set -Ee` environment, if error_recovery's internal commands fail,
# the ERR trap triggers again causing infinite recursion.
# Expected fix: `trap - ERR` at the start of error_recovery().
printf '\n─── Bug 1.3: ERR trap 级联 ───\n'

# Check if error_recovery() disables ERR trap at entry
# Extract lines between error_recovery() { and the first real statement
in_func=0
has_trap_disable=0
while IFS= read -r line; do
    if [[ "$line" =~ ^error_recovery\(\) ]]; then
        in_func=1
        continue
    fi
    if (( in_func )); then
        # Skip opening brace, empty lines, and comments
        [[ "$line" =~ ^[[:space:]]*\{?[[:space:]]*$ ]] && continue
        [[ "$line" =~ ^[[:space:]]*# ]] && continue
        # First real statement should be 'trap - ERR'
        if [[ "$line" == *"trap - ERR"* ]] || [[ "$line" == *"trap '' ERR"* ]]; then
            has_trap_disable=1
        fi
        break
    fi
done < "$SCRIPT"

if (( has_trap_disable )); then
    bug_pass "Bug 1.3: error_recovery disables ERR trap at entry"
else
    bug_fail "Bug 1.3: error_recovery() does NOT disable ERR trap - cascade recursion possible under set -Ee"
fi

# ── Bug 1.4: check_upgrade() blank after "引导磁盘:" when detect_boot_disk is empty ──
# When detect_boot_disk returns empty string (exit 0), the `||` fallback doesn't
# trigger because exit code is 0. Expected fix: use ${var:-未检测到} pattern.
printf '\n─── Bug 1.4: 空引导磁盘 ───\n'

# Check the SPECIFIC line in check_upgrade() function (around line 855)
# The bug is: echo "  引导磁盘: $(detect_boot_disk || echo '未检测到')"
# This fails because detect_boot_disk returns "" with exit 0, so || never fires.
# The fix should use a variable with ${var:-未检测到} parameter expansion.

# Look for the check_upgrade function's boot disk display line specifically
check_upgrade_boot_line=$(sed -n '/^check_upgrade()/,/^[a-zA-Z_]*() *{/p' "$SCRIPT" \
    | grep '引导磁盘')

if echo "$check_upgrade_boot_line" | grep -qF '${'; then
    # Uses parameter expansion (fixed pattern)
    bug_pass "Bug 1.4: check_upgrade uses parameter expansion for empty boot disk"
else
    # Uses $(detect_boot_disk || echo '未检测到') which fails on empty-string-with-exit-0
    bug_fail "Bug 1.4: check_upgrade() uses '|| echo' fallback which won't trigger when detect_boot_disk returns empty string with exit 0 - shows blank instead of '未检测到'"
fi

# ── Bug 1.5: get_efi_dir() picks first vfat partition (non-ESP) ──────────────
# When multiple vfat partitions exist (e.g., USB drive mounted before ESP),
# `findmnt -t vfat | head -1` picks the first one regardless of whether it's ESP.
# Expected fix: prefer path containing "efi" or check PARTTYPE GUID.
printf '\n─── Bug 1.5: EFI 多 vfat 分区误判 ───\n'

# Check if get_efi_dir's findmnt branch filters for "efi" in path
# before taking head -1
efi_findmnt_section=$(sed -n '/^get_efi_dir()/,/^}/p' "$SCRIPT" \
    | sed -n '/findmnt/,/return/p' | head -10)

if echo "$efi_findmnt_section" | grep -qi 'grep.*efi'; then
    bug_pass "Bug 1.5: get_efi_dir filters for 'efi' in findmnt output before head -1"
else
    bug_fail "Bug 1.5: get_efi_dir() uses 'findmnt -t vfat | head -1' without filtering for efi path - picks first arbitrary vfat mount (e.g., USB) instead of ESP"
fi

# ── Bug 1.6: self_update_mode() no write permission check ────────────────────
# self_update_mode() has no permission check at entry. If run as non-root on a
# root-owned script, it proceeds to download but fails at the write step.
# Expected fix: check -w permission at function entry.
printf '\n─── Bug 1.6: self_update 权限检查 ───\n'

# Check the first 15 lines of self_update_mode for a permission check
func_head=$(sed -n '/^self_update_mode()/,/^[a-zA-Z_]*() *{/p' "$SCRIPT" | head -15)

if echo "$func_head" | grep -qE '\-w.*realpath|\-w.*\$0|check_root'; then
    bug_pass "Bug 1.6: self_update_mode has write permission check"
elif echo "$func_head" | grep -qE '\[\[.*\-w'; then
    bug_pass "Bug 1.6: self_update_mode checks write permission"
else
    bug_fail "Bug 1.6: self_update_mode() has NO permission check - non-root user will fail at write step without clear error"
fi

# ── Summary ──────────────────────────────────────────────────────────────────
printf '\n══ Bug Exploration Summary ══\n'
printf '  Passed: %d | Failed: %d\n' "$BUG_TESTS_PASSED" "$BUG_TESTS_FAILED"
if (( BUG_TESTS_FAILED > 0 )); then
    printf '\n  Failures (expected on unfixed code - proves bugs exist):\n'
    printf '%b' "$BUG_TESTS_ERRORS"
    printf '\n  NOTE: These failures CONFIRM the bugs exist in current code.\n'
    printf '  After fixes are applied, all tests should PASS.\n'
    # Don't exit - continue to preservation tests so they can also run
fi

# ═══════════════════════════════════════════════════════════════════════════════
# Preservation Tests
# These tests capture EXISTING correct behavior that must NOT regress.
# They MUST PASS on the current (unfixed) code.
# After fixes are applied, they should STILL PASS.
# ═══════════════════════════════════════════════════════════════════════════════

PRES_TESTS_PASSED=0
PRES_TESTS_FAILED=0
PRES_TESTS_ERRORS=""

pres_pass() {
    PRES_TESTS_PASSED=$((PRES_TESTS_PASSED + 1))
    printf '  ✅ PASS: %s\n' "$1"
}

pres_fail() {
    PRES_TESTS_FAILED=$((PRES_TESTS_FAILED + 1))
    PRES_TESTS_ERRORS="${PRES_TESTS_ERRORS}  FAIL: $1\n"
    printf '  ❌ FAIL: %s\n' "$1"
}

printf '\n══ Preservation Tests (must PASS on unfixed code) ══\n'

# ── Preservation 3.1: Cleanup flow has all 5 steps in correct order ──────────
# Verify cleanup_mode() contains all 5 cleanup steps in the correct order:
# 1. autoremove, 2. rc cleanup, 3. old kernels, 4. APT cache, 5. dpkg config
printf '\n─── Preservation 3.1: Cleanup flow ───\n'

cleanup_body=$(sed -n '/^cleanup_mode()/,/^[a-zA-Z_]*() *{/p' "$SCRIPT" | head -80)

# Check all 5 steps exist and are in order by verifying step labels
has_step1=$(echo "$cleanup_body" | grep -c '步骤 1/5' || echo 0)
has_step2=$(echo "$cleanup_body" | grep -c '步骤 2/5' || echo 0)
has_step3=$(echo "$cleanup_body" | grep -c '步骤 3/5' || echo 0)
has_step4=$(echo "$cleanup_body" | grep -c '步骤 4/5' || echo 0)
has_step5=$(echo "$cleanup_body" | grep -c '步骤 5/5' || echo 0)

if (( has_step1 > 0 && has_step2 > 0 && has_step3 > 0 && has_step4 > 0 && has_step5 > 0 )); then
    pres_pass "Preservation 3.1a: cleanup_mode has all 5 steps labeled"
else
    pres_fail "Preservation 3.1a: cleanup_mode missing step labels (found: 1=$has_step1, 2=$has_step2, 3=$has_step3, 4=$has_step4, 5=$has_step5)"
fi

# Verify the content of each step: autoremove, rc/dpkg --list, old kernels, apt cache, dpkg config
has_autoremove=$(echo "$cleanup_body" | grep -c 'autoremove' || echo 0)
has_rc_cleanup=$(echo "$cleanup_body" | grep -c 'dpkg --list\|dpkg --purge' || echo 0)
has_old_kernels=$(echo "$cleanup_body" | grep -c 'get_old_kernels\|旧内核' || echo 0)
has_apt_cache=$(echo "$cleanup_body" | grep -c 'apt-get.*clean' || echo 0)
has_dpkg_config=$(echo "$cleanup_body" | grep -c 'dpkg-old\|dpkg-dist\|dpkg-bak' || echo 0)

if (( has_autoremove > 0 && has_rc_cleanup > 0 && has_old_kernels > 0 && has_apt_cache > 0 && has_dpkg_config > 0 )); then
    pres_pass "Preservation 3.1b: cleanup_mode has correct content (autoremove, rc, kernels, APT cache, dpkg config)"
else
    pres_fail "Preservation 3.1b: cleanup_mode missing expected content (autoremove=$has_autoremove, rc=$has_rc_cleanup, kernels=$has_old_kernels, cache=$has_apt_cache, dpkg=$has_dpkg_config)"
fi

# Verify step order by checking line numbers
step1_line=$(echo "$cleanup_body" | grep -n '步骤 1/5' | head -1 | cut -d: -f1)
step2_line=$(echo "$cleanup_body" | grep -n '步骤 2/5' | head -1 | cut -d: -f1)
step3_line=$(echo "$cleanup_body" | grep -n '步骤 3/5' | head -1 | cut -d: -f1)
step4_line=$(echo "$cleanup_body" | grep -n '步骤 4/5' | head -1 | cut -d: -f1)
step5_line=$(echo "$cleanup_body" | grep -n '步骤 5/5' | head -1 | cut -d: -f1)

if (( step1_line < step2_line && step2_line < step3_line && step3_line < step4_line && step4_line < step5_line )); then
    pres_pass "Preservation 3.1c: cleanup steps are in correct sequential order (1<2<3<4<5)"
else
    pres_fail "Preservation 3.1c: cleanup steps out of order (lines: $step1_line, $step2_line, $step3_line, $step4_line, $step5_line)"
fi

# ── Preservation 3.2: Upgrade version detection ─────────────────────────────
# Verify get_version_info and get_next_version work correctly for known inputs
printf '\n─── Preservation 3.2: Upgrade version detection ───\n'

# Test version 12 → codename bookworm
v12_info=$(get_version_info 12)
v12_codename=$(echo "$v12_info" | cut -d'|' -f1)

if [[ "$v12_codename" == "bookworm" ]]; then
    pres_pass "Preservation 3.2a: Debian 12 codename is 'bookworm'"
else
    pres_fail "Preservation 3.2a: Debian 12 codename expected 'bookworm', got '$v12_codename'"
fi

# Test version 12 next → 13
v12_next=$(get_next_version 12)
if [[ "$v12_next" == "13" ]]; then
    pres_pass "Preservation 3.2b: Debian 12 next version is 13"
else
    pres_fail "Preservation 3.2b: Debian 12 next version expected '13', got '$v12_next'"
fi

# Test version 13 → codename trixie, status stable
v13_info=$(get_version_info 13)
v13_codename=$(echo "$v13_info" | cut -d'|' -f1)
v13_status=$(echo "$v13_info" | cut -d'|' -f2)

if [[ "$v13_codename" == "trixie" && "$v13_status" == "stable" ]]; then
    pres_pass "Preservation 3.2c: Debian 13 is 'trixie|stable'"
else
    pres_fail "Preservation 3.2c: Debian 13 expected 'trixie|stable', got '$v13_info'"
fi

# ── Preservation 3.3: Error recovery messaging ──────────────────────────────
# Verify error_recovery function body contains error code output and repair suggestion
printf '\n─── Preservation 3.3: Error recovery messaging ───\n'

error_recovery_body=$(sed -n '/^error_recovery()/,/^}/p' "$SCRIPT")

# Check it outputs the error code
has_error_code=$(echo "$error_recovery_body" | grep -c '退出码\|exit.*code\|错误' || echo 0)
if (( has_error_code > 0 )); then
    pres_pass "Preservation 3.3a: error_recovery outputs error code information"
else
    pres_fail "Preservation 3.3a: error_recovery missing error code output"
fi

# Check it has repair suggestion (fix-only recommendation)
has_repair_suggestion=$(echo "$error_recovery_body" | grep -c 'fix-only\|修复\|再运行' || echo 0)
if (( has_repair_suggestion > 0 )); then
    pres_pass "Preservation 3.3b: error_recovery contains repair suggestion messages"
else
    pres_fail "Preservation 3.3b: error_recovery missing repair suggestion"
fi

# Check it mentions log preservation
has_log_preserve=$(echo "$error_recovery_body" | grep -c 'KEEP_RUN_DIR\|日志\|log' || echo 0)
if (( has_log_preserve > 0 )); then
    pres_pass "Preservation 3.3c: error_recovery preserves diagnostic logs"
else
    pres_fail "Preservation 3.3c: error_recovery missing log preservation"
fi

# ── Preservation 3.4: Valid boot disk display ────────────────────────────────
# Verify check_upgrade output format includes boot disk line (the display template exists)
printf '\n─── Preservation 3.4: Valid boot disk display ───\n'

check_upgrade_body=$(sed -n '/^check_upgrade()/,/^[a-zA-Z_]*() *{/p' "$SCRIPT")

# Verify the function has a "引导磁盘" display line
has_boot_disk_line=$(echo "$check_upgrade_body" | grep -c '引导磁盘' || echo 0)
if (( has_boot_disk_line > 0 )); then
    pres_pass "Preservation 3.4a: check_upgrade has boot disk display line"
else
    pres_fail "Preservation 3.4a: check_upgrade missing '引导磁盘' display line"
fi

# Verify detect_boot_disk is called in the display
has_detect_call=$(echo "$check_upgrade_body" | grep -c 'detect_boot_disk' || echo 0)
if (( has_detect_call > 0 )); then
    pres_pass "Preservation 3.4b: check_upgrade calls detect_boot_disk for display"
else
    pres_fail "Preservation 3.4b: check_upgrade not calling detect_boot_disk"
fi

# Verify the output also shows boot mode
has_boot_mode=$(echo "$check_upgrade_body" | grep -c '启动模式.*detect_boot_mode' || echo 0)
if (( has_boot_mode > 0 )); then
    pres_pass "Preservation 3.4c: check_upgrade displays boot mode"
else
    pres_fail "Preservation 3.4c: check_upgrade missing boot mode display"
fi

# ── Preservation 3.5: Single ESP detection ───────────────────────────────────
# Verify get_efi_dir() has the common-path fallback (/boot/efi, /efi, /boot/EFI)
# which works for single ESP systems where findmnt is unavailable
printf '\n─── Preservation 3.5: Single ESP detection ───\n'

efi_dir_body=$(sed -n '/^get_efi_dir()/,/^}/p' "$SCRIPT")

# Check it has common-path fallback (方式2)
has_boot_efi=$(echo "$efi_dir_body" | grep -c '/boot/efi' || echo 0)
has_efi_standalone=$(echo "$efi_dir_body" | grep -c ' /efi' || echo 0)
has_boot_EFI=$(echo "$efi_dir_body" | grep -c '/boot/EFI' || echo 0)

if (( has_boot_efi > 0 && has_efi_standalone > 0 && has_boot_EFI > 0 )); then
    pres_pass "Preservation 3.5a: get_efi_dir has all common-path fallbacks (/boot/efi, /efi, /boot/EFI)"
else
    pres_fail "Preservation 3.5a: get_efi_dir missing common-path fallbacks (boot/efi=$has_boot_efi, /efi=$has_efi_standalone, boot/EFI=$has_boot_EFI)"
fi

# Check it has fstab fallback (方式3)
has_fstab=$(echo "$efi_dir_body" | grep -c 'fstab' || echo 0)
if (( has_fstab > 0 )); then
    pres_pass "Preservation 3.5b: get_efi_dir has /etc/fstab fallback"
else
    pres_fail "Preservation 3.5b: get_efi_dir missing /etc/fstab fallback"
fi

# Check it uses findmnt as primary method
has_findmnt=$(echo "$efi_dir_body" | grep -c 'findmnt' || echo 0)
if (( has_findmnt > 0 )); then
    pres_pass "Preservation 3.5c: get_efi_dir uses findmnt as primary detection method"
else
    pres_fail "Preservation 3.5c: get_efi_dir missing findmnt detection"
fi

# ── Preservation 3.6: Root self-update flow ──────────────────────────────────
# Verify self_update_mode() contains download, verify (bash -n), backup, and replace logic
printf '\n─── Preservation 3.6: Root self-update flow ───\n'

self_update_body=$(sed -n '/^self_update_mode()/,/^[a-zA-Z_]*() *{/p' "$SCRIPT")

# Check download logic (wget + CDN fallback)
has_download=$(echo "$self_update_body" | grep -c 'wget.*-O\|下载' || echo 0)
if (( has_download > 0 )); then
    pres_pass "Preservation 3.6a: self_update_mode has download logic"
else
    pres_fail "Preservation 3.6a: self_update_mode missing download logic"
fi

# Check syntax verification (bash -n)
has_verify=$(echo "$self_update_body" | grep -c 'bash -n' || echo 0)
if (( has_verify > 0 )); then
    pres_pass "Preservation 3.6b: self_update_mode verifies syntax with bash -n"
else
    pres_fail "Preservation 3.6b: self_update_mode missing bash -n verification"
fi

# Check backup logic
has_backup=$(echo "$self_update_body" | grep -c 'backup\|\.bak\|备份' || echo 0)
if (( has_backup > 0 )); then
    pres_pass "Preservation 3.6c: self_update_mode creates backup before replacing"
else
    pres_fail "Preservation 3.6c: self_update_mode missing backup logic"
fi

# Check replace logic (cat > realpath)
has_replace=$(echo "$self_update_body" | grep -c 'cat.*realpath\|> .*(realpath' || echo 0)
if (( has_replace > 0 )); then
    pres_pass "Preservation 3.6d: self_update_mode has replace logic (cat to realpath)"
else
    pres_fail "Preservation 3.6d: self_update_mode missing replace logic"
fi

# Check CDN fallback
has_cdn_fallback=$(echo "$self_update_body" | grep -c 'CDN\|cdn\|jsdelivr' || echo 0)
if (( has_cdn_fallback > 0 )); then
    pres_pass "Preservation 3.6e: self_update_mode has CDN fallback for downloads"
else
    pres_fail "Preservation 3.6e: self_update_mode missing CDN fallback"
fi

# ── Preservation Summary ─────────────────────────────────────────────────────
printf '\n══ Preservation Tests Summary ══\n'
printf '  Passed: %d | Failed: %d\n' "$PRES_TESTS_PASSED" "$PRES_TESTS_FAILED"
if (( PRES_TESTS_FAILED > 0 )); then
    printf '\n  Failures (UNEXPECTED - these should pass on unfixed code):\n'
    printf '%b' "$PRES_TESTS_ERRORS"
    exit 1
fi

# ── Final Summary ────────────────────────────────────────────────────────────
printf '\n══ Overall Test Summary ══\n'
printf '  Bug Exploration: %d passed, %d failed\n' "$BUG_TESTS_PASSED" "$BUG_TESTS_FAILED"
printf '  Preservation:    %d passed, %d failed\n' "$PRES_TESTS_PASSED" "$PRES_TESTS_FAILED"

if (( PRES_TESTS_FAILED > 0 )); then
    printf '\n  ⛔ Preservation test failures indicate broken baseline!\n'
    exit 1
elif (( BUG_TESTS_FAILED > 0 )); then
    printf '\n  ℹ️  Bug exploration failures are EXPECTED on unfixed code.\n'
    exit 42
else
    printf '\n  ✅ All tests passed.\n'
    exit 0
fi
