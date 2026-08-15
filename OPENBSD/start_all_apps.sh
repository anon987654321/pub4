#!/bin/ksh
# Start every pub4 service on vm23 and pin them against resource_guard shedding.
# Usage: doas ksh /home/dev/pub4/OPENBSD/start_all_apps.sh

set -e

ROOT=/home/dev/pub4
ALL_APPS_FLAG=/var/db/pub4_all_apps
SERVICES="master brgen amber bsdports"

install -d -m 755 /var/db
: > "$ALL_APPS_FLAG"
chmod 644 "$ALL_APPS_FLAG"

for svc in $SERVICES; do
  rcctl enable "$svc" 2>/dev/null || true
  rcctl start "$svc" 2>/dev/null || true
done

sleep 5
rcctl restart relayd

for svc in $SERVICES; do
  rcctl check "$svc" || exit 1
done

ruby34 "$ROOT/OPENBSD/health_check.rb" --all-ready-apps
echo "all apps up (resource_guard shedding disabled via $ALL_APPS_FLAG)"
