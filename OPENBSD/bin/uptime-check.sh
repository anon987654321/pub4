#!/usr/bin/env sh
# External-style uptime checker — public HTTPS only, no vm23 tools needed.
# Runs from a laptop or vm23.
#
# Usage:
#   sh OPENBSD/bin/uptime-check.sh
#   CURL=/usr/local/bin/curl sh OPENBSD/bin/uptime-check.sh
#   UPTIME_CHECK_TIMEOUT=40 sh OPENBSD/bin/uptime-check.sh
#
# Exit 0 only when every endpoint returns HTTP 2xx/3xx.
#
# A wrapper, not a list of URLs of its own. health_check.rb asks the same
# question against RAILS/apps.yml, and a hardcoded copy can only go stale — it
# would still name four domains after a fifth app ships, and nothing would
# report that. --public-only is the scope that needs no
# rcctl, no pfctl and no /etc/relayd.conf, which is what made this a wrapper
# rather than a deletion: the entry point is documented in RUNBOOK.md and
# RAILS/amber/HEIR.md, and it is the one health check that runs anywhere.

set -eu

ROOT=$(CDPATH='' cd -- "$(dirname -- "$0")/../.." && pwd)
RUBY=${RUBY:-$(command -v ruby34 2>/dev/null || command -v ruby)}

# Same names this script has always documented, mapped onto health_check.rb's.
HEALTH_CHECK_TIMEOUT=${UPTIME_CHECK_TIMEOUT:-20}
export HEALTH_CHECK_TIMEOUT

exec "$RUBY" "${ROOT}/OPENBSD/health_check.rb" --public-only --all-ready-apps "$@"
