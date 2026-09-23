# frozen_string_literal: true

# Run bsdports' nightly ports-tree import and say what happened, on stdout.
#
# PortsImportJob has no enqueuer while bsdports holds no resident Solid Queue
# worker, the same gap DeclutterHygieneJob has: drain-jobs.sh only starts a
# worker for a queue that already has due rows, so a job whose only trigger
# is its own recurring schedule can never get the worker it needs to be
# enqueued in the first place.
#
# Calls Ports::Importer directly rather than through the job. PortsImportJob
# does the same call and then only forwards the result to an event; running
# the importer here directly means Result#ports_count is available to report
# instead of being swallowed by the job's own return value.
#
# Fed to `bin/rails runner` by ports-import.sh, which is what cron calls.
#
# Pub4::LoadAverage lives in shared/lib, which no app autoloads (only app/* is
# on config.autoload_paths — see shared/lib/shared/engine.rb). prune_guests.rb
# gets it for free because PruneGuestUsersJob happens to require it; nothing
# here does that incidentally, so it needs its own require.
require "operator/load_average"

started = Time.now
platform = Platform.active.find_by!(slug: "openbsd")
result = Ports::Importer.call(platform:)

puts format(
  "platform=%s ports_count=%d tree_path=%s in %.1fs load=%s",
  platform.slug, result.ports_count, result.tree_path, Time.now - started, Pub4::LoadAverage.one.inspect
)
