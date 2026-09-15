#!/usr/bin/env ruby
# frozen_string_literal: true

# Prove that an app's background jobs actually get run.
#
# vm23 runs jobs two ways. brgen has a resident worker, rc.d/brgen_jobs, listed
# in pkg_scripts because it is the one this 1 GB box can hold. amber and
# bsdports have none: rc.d/amber_jobs and rc.d/bsdports_jobs stay off, and
# /usr/local/bin/drain-jobs.sh runs their queues hourly. A proof that asked only
# for a registered SolidQueue::Process would fail those two for doing what was
# decided, and because vps-deploy exits 1 on it, the pass would halt before them.
#
# What the gate is for: an app whose jobs never run is an app whose
# disappearing messages never disappear and whose database never gets
# snapshotted. So there are two ways to pass and both are evidence of work
# being done:
#
#   1. a supervisor is registered — the resident worker
#   2. the cron drain ran for this app recently — the hourly drain
#
# The adapter check hard-fails either way. An app that is not on SolidQueue at
# all is misconfigured no matter who runs the jobs.

require "shellwords"
require "time"

module SolidQueueProof
  DRAIN_LOG = "/var/log/drain-jobs.log"
  # drain-jobs.sh is scheduled hourly at :05. Two hours tolerates one missed
  # tick — the script skips its run when load stays over its ceiling — without
  # tolerating a drain that has silently stopped for a day.
  MAX_DRAIN_AGE_S = 7200

  module_function

  # Lines look like:
  #   2026-08-18T02:08:07Z brgen due 11 -> 2  ahead=48 failed=0 (ran 180s)
  #   2026-08-18T02:08:07Z amber nothing due (ahead=0 failed=0)
  #
  # "nothing due" still counts. It is the drain reporting that it looked at this
  # app and found no work, which is proof it ran, not proof it was idle.
  def last_drain_at(app, log_path: DRAIN_LOG)
    return nil unless File.readable?(log_path)

    stamp = nil
    File.foreach(log_path) do |line|
      fields = line.split
      next unless fields[1] == app

      parsed = (Time.parse(fields[0]) rescue nil)
      stamp = parsed if parsed
    end
    stamp
  end

  def drain_recent?(app, now: Time.now, log_path: DRAIN_LOG, max_age: MAX_DRAIN_AGE_S)
    at = last_drain_at(app, log_path: log_path)
    return false unless at

    (now - at) <= max_age
  end

  # 0 a worker is registered, 3 the adapter is right but nothing is registered,
  # 1 the app is not on SolidQueue. Three rather than a boolean because "no
  # resident worker" is the normal state here and must be distinguishable from
  # "misconfigured", which the old script could not do.
  def runner_source(app, tries)
    <<~RUBY
      adapter = ActiveJob::Base.queue_adapter
      unless adapter.is_a?(ActiveJob::QueueAdapters::SolidQueueAdapter)
        warn "solid_queue: #{app} adapter=\#{adapter.class.name}"
        exit 1
      end

      n = 0
      #{tries}.times do |i|
        n = SolidQueue::Process.count
        break if n.positive?

        sleep 2 unless i == #{tries} - 1
      end

      if n.positive?
        warn "solid_queue: #{app} processes=\#{n}"
        exit 0
      end

      warn "solid_queue: #{app} adapter present, no resident worker registered"
      exit 3
    RUBY
  end

  def load_env(app)
    # The same one file rc.d/<app> hands the running app.
    path = "/etc/#{app}.env"
    return unless File.readable?(path)

    File.foreach(path) do |line|
      key, value = line.strip.split("=", 2)
      next if key.nil? || key.start_with?("#") || value.nil?

      ENV[key] = value
    end
  end

  def main(argv)
    app = argv.fetch(0) { abort "usage: solid_queue_proof.rb APP" }
    app_dir = "/home/#{app}/app"
    abort "missing #{app_dir}" unless File.directory?(app_dir)

    load_env(app)
    secret = ENV.fetch("SECRET_KEY_BASE", "")
    abort "missing SECRET_KEY_BASE in /etc/#{app}.env" if secret.empty?

    drained = drain_recent?(app)
    # Waiting 30 seconds for a worker an app does not run is 30 seconds per app
    # on every deploy. When the drain already proves the work is being
    # done, look once and move on; when it does not, give a starting supervisor
    # the full window before calling it dead.
    tries = drained ? 1 : 15

    cmd = [
      "su", "-m", app, "-c",
      [
        "export HOME=/home/#{app}",
        "cd #{Shellwords.escape(app_dir)}",
        "env RAILS_ENV=production SECRET_KEY_BASE=#{Shellwords.escape(secret)} " \
          "bundle34 exec rails runner -e production #{Shellwords.escape(runner_source(app, tries))}",
      ].join(" && "),
    ]

    system(*cmd)
    status = $?.exitstatus

    case status
    when 0 then exit 0
    when 3
      if drained
        at = last_drain_at(app)
        warn "solid_queue: #{app} jobs run by the hourly drain, last at #{at&.utc&.iso8601}"
        exit 0
      end
      warn "solid_queue: #{app} has no resident worker AND no drain in the last " \
           "#{MAX_DRAIN_AGE_S / 3600}h — nothing is running this app's jobs. " \
           "Check /var/log/drain-jobs.log and the drain-jobs.sh cron entry."
      exit 1
    else exit 1
    end
  end
end

SolidQueueProof.main(ARGV) if $PROGRAM_NAME == __FILE__
