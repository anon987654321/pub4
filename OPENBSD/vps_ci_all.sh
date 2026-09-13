#!/usr/bin/env zsh
# Run all active Rails app CIs serially on vm23 — never parallel.
# Usage: zsh OPENBSD/vps_ci_all.sh      (PUB4_CI_MAX_LOAD=4 waits while load is higher)
set -euo pipefail

if [[ ${1:-} == -h || ${1:-} == --help ]]; then
  print "usage: zsh OPENBSD/vps_ci_all.sh — vps_ci.sh for every app in RAILS/apps.yml, serially"
  exit 0
fi

repo=${PUB4_ROOT:-/home/dev/pub4}
script=${repo}/OPENBSD/vps_ci.sh
# The fleet is apps.yml's, in its order; a literal list here keeps testing three
# apps after a fourth ships.
apps=(${(f)"$(ruby34 -ryaml -e 'puts YAML.safe_load_file(ARGV[0]).fetch("apps").keys' "${repo}/RAILS/apps.yml")"})
(( ${#apps} )) || { print -u2 "vps_ci_all: no apps read from ${repo}/RAILS/apps.yml"; exit 1 }
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
