#!/bin/ksh
set -euo pipefail
# curl is a package (/usr/local/bin/curl) and resource_guard.sh calls this from
# root's cron, whose PATH has no /usr/local/bin — so the /up wait below could
# only ever time out on the path that actually matters, and every crisis
# restart logged "still down after 75s" whether or not master had come back.
export PATH=/usr/local/bin:/usr/local/sbin:/usr/bin:/usr/sbin:/bin:/sbin
# Emergency CPU relief for saturated VPS (vm23).
# Run: doas ksh /home/dev/pub4/OPENBSD/emergency_cpu.sh
#
# Typical cause: Falcon crash-loops, hung bundle install, assets:precompile on restart.

# Prefer the root-owned installed copy; this script is run as root, and
# dot-sourcing from the dev-owned checkout makes repo write access equivalent to
# root code execution. The repo path stays as a fallback for a laptop/dev run,
# where the checkout is already the operator's own.
GUARD_HELPER=/usr/local/libexec/stale_ci_cleanup.ksh
GUARD_REPO=${GUARD_REPO:-/home/dev/pub4}
if [[ -f $GUARD_HELPER ]]; then
  . "$GUARD_HELPER"
elif [[ -f ${GUARD_REPO}/OPENBSD/usr/local/libexec/stale_ci_cleanup.ksh ]]; then
  # Laptop/dev fallback only — on the VM the installed copy above wins.
  . ${GUARD_REPO}/OPENBSD/usr/local/libexec/stale_ci_cleanup.ksh
fi

echo "=== before ==="
uptime
top -b -n1 | head -18

echo "=== stop optional app services ==="
for svc in amber bsdports litestream; do
  rcctl stop "$svc" 2>/dev/null && echo "stopped $svc" || echo "already down $svc"
done

echo "=== kill stale CI/scan workers ==="
if typeset -f stale_ci_cleanup >/dev/null 2>&1; then
  stale_ci_cleanup 99 0
fi

echo "=== kill orphan compile/boot processes ==="
for pat in \
  'bundle install' \
  'bundle34 install' \
  'gem install' \
  'assets:precompile' \
  'assets:build_face' \
  'bin/rails db:seed' \
  'bin/rails test' \
  'ruby.*bin/cli' \
  'MASTER/web/script/probe_face' \
  'tts-worker --daemon'
do
  pkill -f "$pat" 2>/dev/null && echo "pkill $pat" || true
done

echo "=== stop wedged Falcon workers (master + brgen) ==="
pkill -f 'falcon.*53187' 2>/dev/null || true
pkill -f 'ruby34.*53187' 2>/dev/null || true
pkill -f 'falcon.*38182' 2>/dev/null || true
pkill -f 'ruby34.*38182' 2>/dev/null || true
pkill -f '/home/brgen/app' 2>/dev/null || true
pkill -f 'pub4/MASTER/web' 2>/dev/null || true
sleep 2

echo "=== restart core (master then brgen) ==="
rcctl stop master 2>/dev/null || true
sleep 1
rcctl start master 2>/dev/null || echo "master start failed"
_i=0
while [[ $_i -lt 25 ]]; do
  curl -fsS -m 4 http://127.0.0.1:53187/up >/dev/null 2>&1 && echo "master /up ok" && break
  sleep 3
  _i=$((_i + 1))
done
[[ $_i -ge 25 ]] && echo "WARN: master /up still down after 75s"

rcctl restart brgen 2>/dev/null || rcctl start brgen 2>/dev/null || echo "brgen restart failed"
rcctl restart relayd 2>/dev/null || true

sleep 3
echo "=== after ==="
uptime
top -b -n1 | head -18
rcctl check master relayd brgen 2>/dev/null || true
relayctl show hosts 2>/dev/null | head -12 || true

echo "Done. git pull, sync rc.d/master (-n 2), then probe: ruby34 MASTER/web/script/probe_http"
