#!/bin/ksh
# Emergency CPU relief for saturated VPS (vm23).
# Run: doas ksh /home/dev/pub4/DEPLOY/openbsd/emergency_cpu.sh
#
# Typical cause: Falcon crash-loops on failed Rails boots + hung bundle install.

set -e

echo "=== before ==="
uptime
top -b -n1 | head -18

echo "=== stop optional app services (keep master + brgen) ==="
for svc in amber_rails bsdports_rails blognet_rails hjerterom_rails baibl litestream; do
  rcctl stop "$svc" 2>/dev/null && echo "stopped $svc" || echo "already down $svc"
done

echo "=== kill stale tts-worker daemons ==="
pkill -f 'tts-worker --daemon' 2>/dev/null || true

echo "=== kill orphan compile/boot processes ==="
pkill -f 'bundle install' 2>/dev/null || true
pkill -f 'gem install' 2>/dev/null || true
pkill -f 'falcon.*38182' 2>/dev/null || true
pkill -f '/home/brgen/app' 2>/dev/null || true

echo "=== keep core infra; restart relayd with throttled checks ==="
pfctl -s info | head -2
rcctl check relayd nsd httpd master 2>/dev/null || true
rcctl restart relayd 2>/dev/null || true

sleep 3
echo "=== after ==="
uptime
top -b -n1 | head -18
relayctl show hosts 2>/dev/null | head -12 || true

echo "Done. Re-enable apps one at a time after bundle install + /up returns 200."