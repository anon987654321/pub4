# frozen_string_literal: true

# This configuration file will be evaluated by Puma. The top-level methods that
# you can invoke are defined in Puma::DSL. The `environment`, `workers`,
# `preload_app!` and `before_fork`/`on_worker_boot` blocks may be removed or
# customized as needed.

# The Puma web server reads RAILS_MAX_THREADS to size its thread pool; SQLite
# is happiest with a modest pool.
max_threads_count = ENV.fetch("RAILS_MAX_THREADS") { 5 }
min_threads_count = ENV.fetch("RAILS_MIN_THREADS") { max_threads_count }
threads min_threads_count, max_threads_count

# Specifies that the worker count should equal the number of processors in production.
worker_count = Integer(ENV.fetch("WEB_CONCURRENCY") { 1 })
if worker_count > 1
  workers worker_count
else
  preload_app!
end

# Specifies the `port` that Puma will listen on to receive requests; default is 3000.
port ENV.fetch("PORT") { 3000 }

# Allow puma to be restarted by `bin/rails restart` inside engines/plugins.
plugin :tmp_restart

# Run the Solid Queue supervisor inside of Puma in production (single-process deploy).
plugin :solid_queue if ENV["SOLID_QUEUE_IN_PUMA"]
