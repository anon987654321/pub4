#!/usr/bin/env zsh
# Run all active Rails app CIs serially on vm23 — never parallel.
# Usage: zsh OPENBSD/vps_ci_all.sh
set -euo pipefail

repo=${PUB4_ROOT:-/home/dev/pub4}
script=${repo}/OPENBSD/vps_ci.sh
apps=(brgen amber bsdports)
max_load=${PUB4_CI_MAX_LOAD:-4}

wait_for_load() {
  local load
  load=$(sysctl -n vm.loadavg 2>/dev/null | awk '{print $2}')
  while awk -v l="${load:-99}" -v m="$max_load" 'BEGIN{exit !(l>m)}'; do
    print "vps_ci_all: load $load > $max_load — sleeping 60s"
    sleep 60
    load=$(sysctl -n vm.loadavg 2>/dev/null | awk '{print $2}')
  done
}

for app in $apps; do
  wait_for_load
  zsh "$script" "$app" || exit $?
  sleep 10
done

print "vps_ci_all: all apps passed"
