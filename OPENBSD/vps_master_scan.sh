#!/usr/bin/env zsh
# MASTER /scan on vm23 — shares CI lock so scan + CI never overlap.
# Usage: zsh OPENBSD/vps_master_scan.sh [scan args...]
set -euo pipefail

repo=${PUB4_ROOT:-/home/dev/pub4}
lock=${PUB4_CI_LOCK:-/var/tmp/pub4-ci.lock}
max_load=${PUB4_CI_MAX_LOAD:-4}

load=$(sysctl -n vm.loadavg 2>/dev/null | awk '{print $2}')
if awk -v l="${load:-99}" -v m="$max_load" 'BEGIN{exit !(l>m)}'; then
  print -u2 "vps_master_scan: load $load exceeds $max_load"
  exit 1
fi

doas sh -c "
  rm -f ${lock}.holder 2>/dev/null || true
  touch $lock 2>/dev/null || true
  chmod 666 $lock 2>/dev/null || true
" 2>/dev/null || true

cd "$repo/MASTER"
print "vps_master_scan: lock $lock $*"
lockf -k "$lock" env MASTER_SCAN_ONLY=1 MASTER_SAFE_MODE=1 bundle34 exec ruby bin/cli "$@"
