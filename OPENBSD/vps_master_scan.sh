#!/usr/bin/env zsh
# MASTER /scan on vm23 — shares CI lock so scan + CI never overlap.
# Usage: zsh OPENBSD/vps_master_scan.sh [scan args...]
set -euo pipefail

repo=${PUB4_ROOT:-/home/dev/pub4}
# Was `lock=${PUB4_CI_LOCK:-/var/tmp/pub4-ci.lock}`, then root chmod 666'ed exactly
# that caller-chosen path in a world-writable directory. The helper keeps the lock
# in root-owned /var/db/pub4 and ignores an override pointing anywhere else.
. "${repo}/OPENBSD/lib/ci_lock.sh"
max_load=${PUB4_CI_MAX_LOAD:-4}

load=$(sysctl -n vm.loadavg 2>/dev/null | awk '{print $2}')
if awk -v l="${load:-99}" -v m="$max_load" 'BEGIN{exit !(l>m)}'; then
  print -u2 "vps_master_scan: load $load exceeds $max_load"
  exit 1
fi

lock=$(pub4_ensure_ci_lock)

cd "$repo/MASTER"
print "vps_master_scan: lock $lock $*"
lockf -k "$lock" env MASTER_SCAN_ONLY=1 MASTER_SAFE_MODE=1 bundle34 exec ruby bin/cli "$@"
