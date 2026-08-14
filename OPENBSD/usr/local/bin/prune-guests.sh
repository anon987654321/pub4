#!/bin/sh
# Nightly guest-row prune, one app at a time, when the box is actually quiet.
#
# This ran from daily.local for exactly one night and removed nothing. Three
# things were wrong and all three are fixed here.
#
# WHEN. daily.local runs at the tail of /etc/daily, which starts at 01:30 and
# has the box at load 4.12 by the time it gets there. PruneGuestUsersJob's own
# ceiling is 3.0, so the guard correctly refused and the job did nothing — the
# schedule and the guard were fighting each other. Its own cron slot at 04:20 is
# after daily(8) has finished and before the morning. And rather than skip a
# whole night if 04:20 happens to be busy, this waits for the load to fall,
# checking every two minutes for up to half an hour. One Rails boot either way.
#
# WHETHER. See prune_guests.rb: brgen's production logger does not write to
# stdout, so the run left no trace at all and could not be told from a crash.
# The result is printed now, with a timestamp, per app.
#
# HOME. cron's environment has HOME=/var/log (see the root crontab), and `su -m`
# preserves it, so bundler announced "`/var/log` is not writable" and relocated
# the home directory on every invocation. HOME is set explicitly below.
#
# bsdports has no `guest` column on users and is deliberately absent.

PATH=/bin:/sbin:/usr/bin:/usr/sbin:/usr/local/bin
export PATH

CEILING=${PRUNE_GUESTS_LOAD_CEILING:-3.0}
WAIT_TICKS=${PRUNE_GUESTS_WAIT_TICKS:-15}
TICK_SECONDS=${PRUNE_GUESTS_TICK_SECONDS:-120}

stamp() {
  date -u +%FT%TZ
}

# 1-minute average against the ceiling. ruby34 because awk is banned in
# committed scripts here and OpenBSD prints the three numbers bare.
load_is_low() {
  ruby34 -e '
    n = `sysctl -n vm.loadavg 2>/dev/null`.scan(/\d+(?:\.\d+)?/)
    exit(1) if n.size < 3
    exit(n[0].to_f <= ARGV[0].to_f ? 0 : 1)
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

for app in brgen amber; do
  [ -d "/home/$app/app" ] || continue

  out=$(su -m "$app" -c "cd /home/$app/app && set -a && . /etc/$app.env && set +a && HOME=/home/$app RAILS_ENV=production /usr/local/bin/ruby34 bin/rails runner /usr/local/bin/prune_guests.rb" 2>&1)
  status=$?

  result=$(printf '%s\n' "$out" | grep '^removed=')

  if [ "$status" -ne 0 ] || [ -z "$result" ]; then
    echo "$(stamp) $app FAILED (exit $status)"
    printf '%s\n' "$out"
    logger -t prune-guests "guest prune failed for $app - see /var/log/prune-guests.log"
    continue
  fi

  echo "$(stamp) $app $result"
done
