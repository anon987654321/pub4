#!/usr/bin/env sh
# Weekly vm23 integrity + public health (serial, mutex-aware). OPERATOR.sh
# installs it to /usr/local/bin and etc/crontab.vm23 runs it Sunday 03:30 as root.
set -eu

ROOT="${PUB4_ROOT:-/home/dev/pub4}"
RUNAS="${PUB4_WEEKLY_USER:-dev}"
LOG=/var/log/pub4/weekly_integrity.log

# root owns the schedule; root reads not one line of the checkout. Everything
# under $ROOT is dev-writable, so sourcing lib/ci_lock.sh or running
# integrity_gate.rb as root hands root to whoever wrote there last — the same
# escalation OPERATOR.sh refuses for config_drift_gate, crontab.vm23 refuses for
# uptime-check, and resource_guard.sh:135 records as having been reachable within
# five minutes. root therefore does three things, all outside the checkout: makes
# the log directory, opens the log, and drops privilege. $0 is the installed
# root-owned copy, so the re-exec runs root's file as dev rather than dev's file
# as root, and the inherited descriptor keeps the log root:wheel 640, which is
# what etc/newsyslog.conf rotates it as. Every gate below only measures, so dev
# is enough to run them; dev is also the account bin/vps-deploy already runs as.
if [ "$(id -u)" -eq 0 ]; then
  mkdir -p /var/log/pub4
  chmod 755 /var/log/pub4
  exec su "$RUNAS" -c "PUB4_ROOT='$ROOT' '$0'" >>"$LOG" 2>&1
fi

# One definition of the lock path; it moved out of world-writable /var/tmp.
. "${ROOT}/OPENBSD/lib/ci_lock.sh"
LOCK=$(pub4_ci_lock_path)

if [ -f "$LOCK" ] && fuser "$LOCK" >/dev/null 2>&1; then
  echo "$(date -u +%FT%TZ) skip: pub4 CI lock held"
  exit 0
fi

echo "== $(date -u +%FT%TZ) weekly integrity start"
cd "$ROOT"
git fetch origin main 2>&1 || true

# Both gates run, whatever the first one says. Under a bare `set -e` a failing
# integrity gate ended the script, so the public health pass was skipped on
# exactly the week something was already wrong — and with the whole run
# redirected into the log, cron had no output to mail and the truncation was
# invisible. The status line below is the report; the exit code carries it to
# anyone who runs this by hand.
status=0
ruby34 OPENBSD/integrity_gate.rb || status=1
ruby34 OPENBSD/health_check.rb --public --all-ready-apps --json || status=1
echo "== $(date -u +%FT%TZ) weekly integrity end status=$status"
exit "$status"
