# frozen_string_literal: true

# Run the guest prune and SAY WHAT HAPPENED, on stdout.
#
# The first attempt at this called the job straight from daily.local and relied
# on Rails.logger. brgen's production logger does not write to stdout, so the
# 2026-08-14 01:30 run left not one line about brgen in /tmp/prune-guests.out —
# only amber's, because amber's logger is configured differently. From the log
# there was no way to tell whether brgen had pruned 20,000 rows, pruned none, or
# crashed before it started. The count answered it later: none.
#
# So the result is printed here rather than logged. A nightly job that cannot be
# told from a nightly crash is the same kind of defect as the job never running.
#
# Fed to `bin/rails runner` by prune-guests.sh, which is what cron calls.

started = Time.now
removed = Shared::PruneGuestUsersJob.new.perform
remaining = ::User.where(guest: true)
                  .where(created_at: ..Shared::PruneGuestUsersJob::RETENTION.ago)
                  .where.missing(:sessions)
                  .count

puts format(
  "removed=%d remaining=%d in %.1fs load=%s",
  removed.to_i, remaining, Time.now - started, Pub4::LoadAverage.one.inspect
)
