#!/usr/bin/env zsh
# Run all active Rails app CIs serially on vm23 — never parallel.
# Usage: zsh OPENBSD/vps_ci_all.sh
set -euo pipefail

repo=${PUB4_ROOT:-/home/dev/pub4}
script=${repo}/OPENBSD/vps_ci.sh
apps=(brgen amber bsdports)
max_load=${PUB4_CI_MAX_LOAD:-4}

# The 5-minute average, and one ruby34 rather than two awks per tick — the same
# shape vps_master_scan.sh uses, for the same two reasons: awk is banned in
# committed scripts here, and one process both reads the figure and decides on
# it, so there is no window where the value read is not the value compared.
# OpenBSD prints the three numbers bare and macOS wraps them in braces, which is
# why this scans for numbers rather than splitting on whitespace.
load_over_max() {
  ruby34 -e '
    n = `sysctl -n vm.loadavg 2>/dev/null`.scan(/\d+(?:\.\d+)?/)
    exit(0) if n.size < 3
    exit(n[1].to_f > ARGV[0].to_f ? 0 : 1)
  ' "$max_load"
}

wait_for_load() {
  while load_over_max; do
    print "vps_ci_all: 5-minute load over $max_load — sleeping 60s"
    sleep 60
  done
}

for app in $apps; do
  wait_for_load
  zsh "$script" "$app" || exit $?
  sleep 10
done

print "vps_ci_all: all apps passed"
