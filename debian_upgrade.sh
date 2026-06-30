#!/usr/bin/env bash
set -Eeuo pipefail

# Backward-compatible wrapper after renaming to distro_upgrade.sh.
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
exec "${SCRIPT_DIR}/distro_upgrade.sh" "$@"
