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

# awk twice, in a repo that bans it in committed scripts. Ruby also spares the
# second invocation: one process reads the load and decides.
load=$(sysctl -n vm.loadavg 2>/dev/null)
if ! ruby34 -e 'n = ARGV[0].to_s.scan(/\d+(?:\.\d+)?/); exit 1 if n.size < 3; exit(n[1].to_f > ARGV[1].to_f ? 1 : 0)' "$load" "$max_load"; then
  print -u2 "vps_master_scan: load ${load:-unreadable} over $max_load (5-minute average)"
  exit 1
fi

lock=$(pub4_ensure_ci_lock)

cd "$repo/MASTER"
print "vps_master_scan: lock $lock $*"
# Was `lockf -k "$lock" ...`. OpenBSD has no lockf(1) — it is a FreeBSD utility —
# so this line was `lockf: Command not found` on every run since it was written,
# and the documented way to scan on vm23 has never taken the lock or run the
# scan. bin/with-ci-lock is the same idea in the one language this box is
# guaranteed to have.
ruby34 "$repo/OPENBSD/bin/with-ci-lock" \
  env MASTER_SCAN_ONLY=1 MASTER_SAFE_MODE=1 bundle34 exec ruby bin/cli "$@"
