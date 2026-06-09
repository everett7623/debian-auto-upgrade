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

# Source functions without executing main.
# shellcheck source=../debian_upgrade.sh
source "$SCRIPT"
trap - EXIT

[[ "$(get_next_version 11)" == "12" ]] || fail "Debian 11 target"
[[ "$(get_next_version 12)" == "13" ]] || fail "Debian 12 target"
[[ -z "$(STABLE_ONLY=1 get_next_version 13)" ]] || fail "stable policy"
[[ "$(STABLE_ONLY=0 get_next_version 13)" == "14" ]] || fail "testing policy"
[[ "$(get_version_info 13)" == "trixie|stable" ]] || fail "Trixie status"

if grep -Eq 'rm[[:space:]]+-f[[:space:]]+/var/(lib/dpkg|cache/apt).*(lock|lock-frontend)' "$SCRIPT"; then
    fail "main script deletes package-manager locks"
fi

if grep -Eq 'dd[[:space:]].*of=.*boot_disk' "$SCRIPT"; then
    fail "main upgrade path contains direct boot-sector write"
fi

printf 'smoke tests passed\n'
