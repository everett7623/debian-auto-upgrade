# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Build & Test

```bash
make check          # Full CI: syntax check + shellcheck + smoke tests
make syntax         # bash -n on all .sh files
make shellcheck     # Static analysis (requires shellcheck)
make test           # Smoke tests only
bash tests/smoke.sh # Run smoke tests directly (no shellcheck)
```

Smoke tests are non-privileged: they source the main script and unit-test version mappings, static invariants (no lock deletion, no MBR writes, single dist-upgrade call), and CLI flag presence in help output.

## Architecture

The entire tool is a single Bash script: `debian_upgrade.sh` (v3.5, ~1365 lines). It is the **only supported production entry point**. Legacy scripts in `scripts/` are historical reference only.

### Execution flow

```
main() → parse args → set_mirror() → check_root() → check_system() → main_upgrade()
  ├── get_current_version()  (4 fallback strategies)
  ├── get_next_version()     (respects STABLE_ONLY gate)
  ├── pre_upgrade_preparation()
  │     ├── stop_apt_units()           → stop systemd apt timers
  │     ├── wait_for_apt_locks()       → fuser-based wait, timeout 300s
  │     ├── check_runtime_injection()  → LD_PRELOAD / fsck dependency audit
  │     ├── check_initramfs_health()   → pre-build initramfs before touching sources
  │     ├── dpkg --audit / --configure -a / --fix-broken (best-effort, no ERR trap)
  │     ├── apt-get install --reinstall debian-archive-keyring  → GPG key update before source switch
  │     └── clean_apt_sources() → backup & disable .list + .sources, comment backports
  ├── Write new /etc/apt/sources.list
  ├── apt-get update (with GPG error recovery: [trusted=yes] → install keyring → remove trust)
  ├── apt-get upgrade        (minimal — aborts on failure, no retry)
  ├── apt-get dist-upgrade   (full — aborts on failure, no retry)
  └── post_upgrade_fixes()
        ├── fix_network_config()   → compare interface names, warn only
        ├── update-initramfs       → only if latest kernel lacks initrd
        └── update-grub            → config refresh only, no grub-install
```

### Version mapping

`get_version_info()` and `get_next_version()` are the central policy tables. They encode:
- Codename and stability status per numeric version
- Whether the next version is reachable (gated by `STABLE_ONLY`)
- `STABLE_ONLY=1` (default): 13→14 is blocked; `STABLE_ONLY=0` (--allow-testing): 13→14 is permitted

When adding a new Debian release, update both functions, `SCRIPT_VERSION`/`SCRIPT_DATE`, the sources.list template (non-free-firmware, security suffix), README support matrix, and CHANGELOG.

### Hard safety invariants (enforced by smoke tests)

- Never delete APT/dpkg lock files (`/var/lib/dpkg/lock*`, `/var/cache/apt/*/lock`)
- Never write directly to boot sectors (no `dd of=...boot_disk`)
- Only one `apt-get dist-upgrade` call in normal flow
- Generated sources.list must not include `deb-src` lines
- `check_initramfs_health`, `check_runtime_injection`, `debian-archive-keyring`, and `[trusted=yes]` path must all be present

### Error handling pattern

The script uses `set -Ee -o pipefail` with a global ERR trap (`error_recovery()`) that stops immediately — it does **not** retry. This is intentional: previous versions repeated failing operations, wasting time without fixing root causes. The trap preserves the run directory (`KEEP_RUN_DIR=1`) so logs survive.

`dpkg --audit` and `dpkg --configure -a` in `pre_upgrade_preparation()` are run with `|| true` because they can return non-zero on already-broken systems, and the ERR trap would otherwise abort before the upgrade even starts.

### Temp directory

Each invocation creates `/tmp/debian-auto-upgrade-<YYYYMMDD_HHMMSS>_<PID>/`. Unless `KEEP_RUN_DIR=1` (set on failure), it is deleted on EXIT via a `trap cleanup EXIT`. On failure, the directory is preserved and its path printed.

## Key files

| File | Purpose |
|------|---------|
| `debian_upgrade.sh` | Single source of truth; all production logic |
| `tests/smoke.sh` | Non-privileged unit tests; sources main script to test functions |
| `Makefile` | CI entry point; wraps bash -n, shellcheck, smoke tests |
| `.github/workflows/ci.yml` | Runs `make check` on ubuntu-latest |
| `docs/SAFETY.md` | Hard safety boundaries (locks, MBR, network, autoremove) |
| `docs/DEVELOPMENT.md` | Dev environment setup and release checklist |
| `scripts/` | Legacy per-version scripts; do not modify or use as reference for current behavior |
