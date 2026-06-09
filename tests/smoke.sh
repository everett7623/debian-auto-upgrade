#!/usr/bin/env bash
set -Eeuo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SCRIPT="${ROOT_DIR}/debian_upgrade.sh"

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

# Source functions without executing main.
# shellcheck source=../debian_upgrade.sh
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

dist_upgrade_count="$(grep -c 'apt-get dist-upgrade' "$SCRIPT")"
[[ "$dist_upgrade_count" == "1" ]] || fail "dist-upgrade should run at most once"

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
