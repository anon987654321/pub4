#!/usr/bin/env sh
# External-style uptime checker — curls /up on each production app.
# Runs from a laptop or vm23; no local gates required.
#
# Usage:
#   sh OPENBSD/bin/uptime-check.sh
#   CURL=/usr/local/bin/curl sh OPENBSD/bin/uptime-check.sh
#
# Exit 0 only when every endpoint returns HTTP 2xx/3xx.

set -eu

CURL=${CURL:-curl}
TIMEOUT=${UPTIME_CHECK_TIMEOUT:-20}

check() {
  name=$1
  url=$2
  if ! $CURL -fsS --max-time "$TIMEOUT" -o /dev/null "$url"; then
    printf 'FAIL %s %s\n' "$name" "$url" >&2
    return 1
  fi
  printf 'ok   %s %s\n' "$name" "$url"
}

failed=0
check master  "https://ai.brgen.no/up"        || failed=1
check brgen   "https://brgen.no/up"          || failed=1
check amber   "https://amber.brgen.no/up"    || failed=1
check bsdports "https://bsdports.org/up"     || failed=1

if [ "$failed" -ne 0 ]; then
  printf 'uptime-check: one or more endpoints failed\n' >&2
  exit 1
fi

printf 'uptime-check: all endpoints ok\n'
