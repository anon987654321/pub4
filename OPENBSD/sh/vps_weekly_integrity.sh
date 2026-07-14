#!/usr/bin/env sh
# Weekly vm23 integrity + public health (serial, mutex-aware). Install in root crontab or daily.local.
set -eu

ROOT="${PUB4_ROOT:-/home/dev/pub4}"
LOCK=/var/tmp/pub4-ci.lock
LOG=/var/log/pub4/weekly_integrity.log

mkdir -p /var/log/pub4 2>/dev/null || doas mkdir -p /var/log/pub4
doas chmod 755 /var/log/pub4 2>/dev/null || true

if [ -f "$LOCK" ] && fuser "$LOCK" >/dev/null 2>&1; then
  echo "$(date -u +%FT%TZ) skip: pub4 CI lock held" >>"$LOG"
  exit 0
fi

{
  echo "== $(date -u +%FT%TZ) weekly integrity start"
  cd "$ROOT"
  git fetch origin main 2>&1 || true
  ruby34 OPENBSD/integrity_gate.rb 2>&1
  ruby34 OPENBSD/health_check.rb --public --all-ready-apps --json 2>&1
  echo "== $(date -u +%FT%TZ) weekly integrity end"
} >>"$LOG" 2>&1