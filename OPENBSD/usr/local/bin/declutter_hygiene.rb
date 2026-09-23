# frozen_string_literal: true

# Run amber's daily declutter hygiene and say what happened, on stdout.
#
# DeclutterHygieneJob has no enqueuer while amber holds no resident Solid
# Queue worker: drain-jobs.sh only starts a worker for a queue that already
# has due rows, so a job whose only trigger is its own recurring schedule --
# nothing else ever enqueues it -- can never get the worker it needs to be
# enqueued in the first place.
#
# Fed to `bin/rails runner` by declutter-hygiene.sh, which is what cron calls.
#
# Operator::LoadAverage lives in shared/lib, which no app autoloads (only
# app/* is on config.autoload_paths — see shared/lib/shared/engine.rb).
# prune_guests.rb gets it for free because PruneGuestUsersJob happens to
# require it; nothing here does that incidentally, so it needs its own
# require.
require "operator/load_average"

started = Time.now
overdue_before = DeclutterChallenge.overdue.count

DeclutterHygieneJob.new.perform

overdue_after = DeclutterChallenge.overdue.count
nudges = Recommendation.declutter.where(created_at: started..).count

puts format(
  "expired_challenges=%d box_nudges=%d in %.1fs load=%s",
  overdue_before - overdue_after, nudges, Time.now - started, Operator::LoadAverage.one.inspect
)
