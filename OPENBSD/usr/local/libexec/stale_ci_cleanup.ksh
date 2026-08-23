#!/bin/ksh
# Kill orphaned CI/scan workers when vm23 is saturated. Sourced by resource_guard.sh.
# Safe-ish: skips falcon/rc.d parents; targets test/seed/ci/cli patterns only.


# set -e and pipefail: a failed step inside a manual deploy used to continue
# to the next one, and with only set -e a failed `sysctl | awk` yields an empty
# string that the caller then compares against nothing.
set -e
set -o pipefail
stale_ci_cleanup() {
  typeset load=${1:-0}
  typeset mem_free=${2:-100}
  typeset STALE_LOAD=4.0

  awk -v l="$load" -v t="$STALE_LOAD" 'BEGIN{exit !(l>=t)}' || return 0

  logger -t resource-guard "stale-ci cleanup load=$load mem_free=${mem_free}%"

  typeset pat
  for pat in \
    'bundle34 exec bin/ci' \
    'bundle exec bin/ci' \
    'bin/rails db:seed' \
    'bin/rails test' \
    'bin/rails dartsass' \
    'ruby.*bin/cli'
  do
    pkill -f "$pat" 2>/dev/null && logger -t resource-guard "stale-ci pkill: $pat"
  done

  pkill -U dev -f 'ruby.*bin/cli' 2>/dev/null || true
}

# heal_doas_conf removed deliberately. It ran at load time, so merely sourcing
# this file made root dot-source validate_doas.ksh from ${GUARD_REPO:-/home/dev/pub4}
# — a dev-owned checkout — and then copy that repo's doas.conf over
# /etc/doas.conf. Two consequences:
#
#   1. Write access to either repo file was root code execution on the next
#      5-minute cron tick, with no doas involved.
#   2. Any hardening of the live /etc/doas.conf was reverted within 5 minutes,
#      and validate_doas_works actively rolled back configs where dev was not
#      root — so the system re-asserted passwordless root for dev.
#
# doas policy must not be auto-synced from a user-writable tree. Change
# /etc/doas.conf deliberately, by hand or via a root-owned installer.
