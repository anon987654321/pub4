#!/bin/ksh
# Unprivileged recovery wrapper. Fleet-wide root actions live only in the fixed broker.
set -eu

case ${1:-} in
  -h|--help)
    echo "usage: ksh OPENBSD/bin/start_all_apps.sh — start the fixed pub4 fleet and pin it against resource_guard shedding"
    exit 0
    ;;
  "") ;;
  *) echo "start_all_apps: no arbitrary arguments are accepted" >&2; exit 2 ;;
esac

if [ "$(id -u)" -eq 0 ]; then
  echo "start_all_apps: refusing to execute checkout code as root; run this as dev" >&2
  exit 2
fi

broker=/usr/local/sbin/pub4-admin
[ -x "$broker" ] && [ ! -L "$broker" ] || {
  echo "start_all_apps: fixed root broker is missing or symlinked; run the reviewed OPERATOR.sh sync first" >&2
  exit 1
}

doas "$broker" start-all-apps

ROOT=/home/dev/pub4
. "$ROOT/OPENBSD/lib/ruby_select.sh"
"$RUBY" "$ROOT/OPENBSD/checks/health_check.rb" --all-ready-apps
echo "all apps up (resource_guard shedding disabled via /var/db/pub4_all_apps)"
