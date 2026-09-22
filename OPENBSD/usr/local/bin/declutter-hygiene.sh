#!/bin/sh
# Nightly amber declutter hygiene, when the box is actually quiet.
#
# DeclutterHygieneJob sits in amber's recurring.yml for 6am, but a recurring
# schedule only fires while a Solid Queue scheduler is resident to notice the
# time has come, and amber holds no resident worker. drain-jobs.sh cannot
# substitute for it: it only starts a worker for an app that already has due
# rows, and this job's sole trigger is the recurring schedule itself, so
# drain-jobs.sh never has a reason to start one. Same load-gate shape as
# prune-guests.sh, next door.

PATH=/bin:/sbin:/usr/bin:/usr/sbin:/usr/local/bin
export PATH

CEILING=${DECLUTTER_HYGIENE_LOAD_CEILING:-3.0}
WAIT_TICKS=${DECLUTTER_HYGIENE_WAIT_TICKS:-15}
TICK_SECONDS=${DECLUTTER_HYGIENE_TICK_SECONDS:-120}

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

out=$(su -m amber -c "cd /home/amber/app && set -a && . /etc/amber.env && set +a && HOME=/home/amber RAILS_ENV=production /usr/local/bin/ruby34 bin/rails runner /usr/local/bin/declutter_hygiene.rb" 2>&1)
status=$?

result=$(printf '%s\n' "$out" | grep '^expired_challenges=')

if [ "$status" -ne 0 ] || [ -z "$result" ]; then
  echo "$(stamp) amber FAILED (exit $status)"
  printf '%s\n' "$out"
  logger -t declutter-hygiene "amber declutter hygiene failed - see /var/log/declutter-hygiene.log"
  exit 1
fi

echo "$(stamp) amber $result"
