#!/bin/sh
# Nightly bsdports ports-tree import, when the box is actually quiet.
#
# PortsImportJob sits in bsdports' recurring.yml for 3am, but a recurring
# schedule only fires while a Solid Queue scheduler is resident to notice the
# time has come, and bsdports holds no resident worker. drain-jobs.sh cannot
# substitute for it: it only starts a worker for an app that already has due
# rows, and this job's sole trigger is the recurring schedule itself, so
# drain-jobs.sh never has a reason to start one. Same load-gate shape as
# prune-guests.sh, next door.

PATH=/bin:/sbin:/usr/bin:/usr/sbin:/usr/local/bin
export PATH

CEILING=${PORTS_IMPORT_LOAD_CEILING:-3.0}
WAIT_TICKS=${PORTS_IMPORT_WAIT_TICKS:-15}
TICK_SECONDS=${PORTS_IMPORT_TICK_SECONDS:-120}

stamp() {
  date -u +%FT%TZ
}

# The 5-minute average, so waiting for it to fall does not spike on the Rails
# boot this wrapper is about to cause. See prune-guests.sh for the measurement
# that found the 1-minute figure self-defeating.
load_is_low() {
  ruby34 -e '
    n = `sysctl -n vm.loadavg 2>/dev/null`.scan(/\d+(?:\.\d+)?/)
    exit(1) if n.size < 3
    exit(n[1].to_f <= ARGV[0].to_f ? 0 : 1)
  ' "$CEILING"
}

wait_for_quiet() {
  i=0
  while [ "$i" -lt "$WAIT_TICKS" ]; do
    if load_is_low; then
      return 0
    fi
    i=$((i + 1))
    sleep "$TICK_SECONDS"
  done
  return 1
}

if ! wait_for_quiet; then
  echo "$(stamp) skipped: load stayed over $CEILING for $((WAIT_TICKS * TICK_SECONDS / 60)) minutes"
  exit 0
fi

out=$(su -m bsdports -c "cd /home/bsdports/app && set -a && . /etc/bsdports.env && set +a && HOME=/home/bsdports RAILS_ENV=production /usr/local/bin/ruby34 bin/rails runner /usr/local/bin/ports_import.rb" 2>&1)
status=$?

result=$(printf '%s\n' "$out" | grep '^platform=')

if [ "$status" -ne 0 ] || [ -z "$result" ]; then
  echo "$(stamp) bsdports FAILED (exit $status)"
  printf '%s\n' "$out"
  logger -t ports-import "bsdports ports import failed - see /var/log/ports-import.log"
  exit 1
fi

echo "$(stamp) bsdports $result"
