#!/bin/sh
# Nightly amber GDPR erasure, when the box is actually quiet.
#
# UserPurgeJob sits in amber's recurring.yml for 3:50am, but a recurring
# schedule only fires while a Solid Queue scheduler is resident to notice the
# time has come, and amber holds no resident worker. drain-jobs.sh cannot
# substitute for it: it only starts a worker for an app that already has due
# rows, and this job's sole trigger is the recurring schedule itself, so
# drain-jobs.sh never has a reason to start one. Same shape as
# declutter-hygiene.sh, next door: load-gated, direct `rails runner`, no Solid
# Queue scheduler required.
#
# This is the compensation for a deletion pipeline with legal teeth (GDPR
# Art. 17): the deletion grace period is 30 days and an erasure that never
# runs is a compliance violation no red check currently catches. If this
# script is failing, fix it before anything else in the queue.

PATH=/bin:/sbin:/usr/bin:/usr/sbin:/usr/local/bin
export PATH

# This installs to /usr/local/bin and cannot source the repo's ruby_select.sh:
# take the first Ruby the packages left beside it.
RUBY=
for _r in ruby4.0 ruby40 ruby3.4 ruby34 ruby3.3 ruby33 ruby; do
  if [ -x "/usr/local/bin/$_r" ]; then RUBY="/usr/local/bin/$_r"; break; fi
done

CEILING=${PURGE_DELETED_USERS_LOAD_CEILING:-3.0}
WAIT_TICKS=${PURGE_DELETED_USERS_WAIT_TICKS:-15}
TICK_SECONDS=${PURGE_DELETED_USERS_TICK_SECONDS:-120}

stamp() {
  date -u +%FT%TZ
}

# The 5-minute average, so waiting for it to fall does not spike on the Rails
# boot this wrapper is about to cause. See prune-guests.sh for the measurement
# that found the 1-minute figure self-defeating.
load_is_low() {
  "$RUBY" -e '
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

out=$(su -m amber -c "cd /home/amber/app && set -a && . /etc/amber.env && set +a && HOME=/home/amber RAILS_ENV=production $RUBY bin/rails runner /usr/local/bin/purge_deleted_users.rb" 2>&1)
status=$?

result=$(printf '%s\n' "$out" | grep '^purged_due=')

if [ "$status" -ne 0 ] || [ -z "$result" ]; then
  echo "$(stamp) amber FAILED (exit $status)"
  printf '%s\n' "$out"
  logger -t purge-deleted-users "amber GDPR erasure failed - see /var/log/purge-deleted-users.log"
  exit 1
fi

echo "$(stamp) amber $result"
