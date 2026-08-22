#!/bin/sh
# set -e with the three deliberate failures guarded below: a drain window
# ending in timeout(1) killing rake IS the design, and an unreadable queue
# db defaults to zero counts rather than aborting the sweep.
set -eo pipefail
# Run the background job queue for a few minutes, hourly, because vm23 cannot
# hold a worker that stays up.
#
# Solid Queue needs its own process under Falcon and none was ever started, so
# `perform_later` on this box meant never. Ten job classes are reached from live
# request paths; on 2026-08-14 brgen was holding 181 unfinished jobs of which
# 178 were MessageExpirationJob — disappearing messages that had never
# disappeared — and amber 28.
#
# A resident worker does not fit, and that is measured rather than assumed. At
# the time of writing the box had 60 MB free with 1032 MB of 1264 MB of swap in
# use, and a Solid Queue supervisor plus its workers came to roughly 460 MB of
# RSS across four processes. Three of those, one per app, is not a thing this
# machine can carry.
#
# A bounded run is. 180 seconds of worker drained 96 of the 181, held the load
# under 2, and the box finished the run with MORE free memory than it started
# (58 MB before, 292 MB after) because starting it made the kernel reclaim.
#
# WHAT THIS DOES NOT FIX: latency. ChannelBotReplyJob is a bot answering someone
# in a chat room, and an answer that arrives up to an hour later is not an
# answer. That one wants a worker that stays up, which wants a bigger box. The
# jobs this does fix are the ones where an hour costs nothing — expiring
# messages, blurhashes, media derivatives, federation, moderation notices.
#
# Same shape as prune-guests.sh next door: wait for quiet, bound the work, and
# print what happened rather than trusting a logger that may not reach anyone.

PATH=/bin:/sbin:/usr/bin:/usr/sbin:/usr/local/bin
export PATH

CEILING=${DRAIN_JOBS_LOAD_CEILING:-3.0}
SECONDS_PER_APP=${DRAIN_JOBS_SECONDS:-180}
WAIT_TICKS=${DRAIN_JOBS_WAIT_TICKS:-5}
TICK_SECONDS=${DRAIN_JOBS_TICK_SECONDS:-60}

stamp() {
  date -u +%FT%TZ
}

# The 5-minute average. The 1-minute figure spikes on anything that starts,
# including the boot this script is about to do, so a gate reading it refuses
# the spike it caused itself — see the header of prune-guests.sh, where that
# cost a night's work before anyone noticed.
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

# Count what is actually RUNNABLE, not what is unfinished.
#
# The first version of this reported unfinished jobs and printed "brgen pending
# 85 -> 85 (ran 150s)", which reads as a worker that did nothing. It had drained
# everything there was: 82 of those 85 were MessageExpirationJob rows scheduled
# hours ahead, which is the feature working, and 1 was a permanently failed job.
# A number that cannot go down is not a progress report.
#
# due            — ready now, or scheduled for a time that has passed
# ahead          — scheduled for later, nothing to do about it
# failed         — gave up after its retries; needs a person, not another tick
queue_counts() {
  su -m "$1" -c "sqlite3 /home/$1/app/storage/production_queue.sqlite3 \"
    select
      (select count(*) from solid_queue_jobs j
        where j.finished_at is null
          and (j.scheduled_at is null or j.scheduled_at <= datetime('now'))
          and not exists (select 1 from solid_queue_failed_executions f where f.job_id = j.id)),
      (select count(*) from solid_queue_jobs j
        where j.finished_at is null and j.scheduled_at > datetime('now')),
      (select count(*) from solid_queue_failed_executions);
  \"" 2>/dev/null
}

# cut, not ruby34 -e: the first version was
#
#   printf '%s\n' "$1" | ruby34 -e 'print(ARGF.read...)' "$2"
#
# and ARGF treats a trailing argument as a FILENAME, so it tried to open "0" and
# died with ENOENT while the caller quietly substituted a default. Every field
# came back 0 and the report read "nothing due (ahead=0 failed=0)" against a
# queue holding 82 scheduled jobs — plausible, and wrong. cut has no such trap.
field() {
  printf '%s\n' "$1" | cut -d'|' -f"$2"
}

if ! wait_for_quiet; then
  echo "$(stamp) skipped: load stayed over $CEILING for $((WAIT_TICKS * TICK_SECONDS / 60)) minutes"
  exit 0
fi

for app in brgen amber bsdports; do
  [ -d "/home/$app/app" ] || continue
  [ -f "/home/$app/app/storage/production_queue.sqlite3" ] || continue

  counts=$(queue_counts "$app") || counts=""
  due=$(field "$counts" 1)
  ahead=$(field "$counts" 2)
  failed=$(field "$counts" 3)
  [ -n "$due" ] || due=0
  [ -n "$ahead" ] || ahead=0
  [ -n "$failed" ] || failed=0

  if [ "$due" -eq 0 ]; then
    echo "$(stamp) $app nothing due (ahead=$ahead failed=$failed)"
    continue
  fi

  # SIGTERM, which Solid Queue handles: it stops claiming new work and lets what
  # is in flight finish. -k gives it 20 seconds before SIGKILL.
  su -m "$app" -c "cd /home/$app/app && set -a && . /etc/$app.env && set +a && HOME=/home/$app RAILS_ENV=production timeout -k 20 -s TERM $SECONDS_PER_APP /usr/local/bin/bundle34 exec rake solid_queue:start" \
    >>/var/log/drain-jobs.detail.log 2>&1 || true

  after=$(queue_counts "$app") || after=""
  echo "$(stamp) $app due $due -> $(field "$after" 1)  ahead=$(field "$after" 2) failed=$(field "$after" 3) (ran ${SECONDS_PER_APP}s)"
done
