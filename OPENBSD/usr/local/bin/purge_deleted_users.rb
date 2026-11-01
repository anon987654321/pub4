# frozen_string_literal: true

# Run amber's GDPR Art. 17 erasure pass and say what happened, on stdout.
#
# UserPurgeJob's sole trigger is its recurring.yml schedule (nothing else ever
# enqueues it), and amber holds no resident Solid Queue scheduler: drain-jobs.sh
# only starts a worker for a queue that already has due rows, so a recurring
# entry can never get the worker it needs to be enqueued in the first place.
# The same trap as DeclutterHygieneJob, and the same cure — a direct
# `bin/rails runner` call from cron (purge-deleted-users.sh).
#
# The job itself is the erasure authority; this file only counts and reports.
# Counting before and after is the check that the run did something: a run
# that reports purged_due=0 on a day the marker table held due rows is a
# failure the wrapper can see.

due_before = User.where.not(deletion_scheduled_at: nil)
                 .where("deletion_scheduled_at <= ?", Time.current).count

started = Time.now
UserPurgeJob.new.perform

due_after = User.where.not(deletion_scheduled_at: nil)
                .where("deletion_scheduled_at <= ?", Time.current).count

puts format(
  "purged_due=%d remaining_due=%d in %.1fs",
  due_before - due_after, due_after, Time.now - started
)
