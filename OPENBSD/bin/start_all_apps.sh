#!/bin/ksh
# Start every pub4 service on vm23 and pin them against resource_guard shedding.
# Usage: doas ksh /home/dev/pub4/OPENBSD/bin/start_all_apps.sh
#
# The services are master plus every app in RAILS/apps.yml, read at run time:
# master is not an apps.yml app, and a literal list keeps starting three apps
# after a fourth ships.

set -eo pipefail

case ${1:-} in
-h|--help)
  echo "usage: doas ksh OPENBSD/bin/start_all_apps.sh — enable and start master and every apps.yml app, pin them against shedding"
  exit 0
  ;;
esac

# Named outright, as the rc.d scripts name it: this runs as root from rc(8) or by
# hand with no caller environment, so a PUB4_ROOT needs setting here too.
# Production has one checkout, and a worktree is never a deploy target.
ROOT=/home/dev/pub4
ALL_APPS_FLAG=/var/db/pub4_all_apps
APPS=$(ruby34 -ryaml -e 'puts YAML.safe_load_file(ARGV[0]).fetch("apps").keys.join(" ")' "$ROOT/RAILS/apps.yml")
[ -n "$APPS" ] || { echo "start_all_apps: no apps read from $ROOT/RAILS/apps.yml" >&2; exit 1; }
SERVICES="master $APPS"

install -d -m 755 /var/db
: > "$ALL_APPS_FLAG"
chmod 644 "$ALL_APPS_FLAG"

for svc in $SERVICES; do
  rcctl enable "$svc" 2>/dev/null || true
  rcctl start "$svc" 2>/dev/null || true
done

# Not a race: each app's rc.d start blocks in its own /up wait, up to 300
# seconds, before it returns, so this restart follows every backend's wait.
sleep 5
rcctl restart relayd

for svc in $SERVICES; do
  rcctl check "$svc" || exit 1
done

ruby34 "$ROOT/OPENBSD/gates/health_check.rb" --all-ready-apps
echo "all apps up (resource_guard shedding disabled via $ALL_APPS_FLAG)"
