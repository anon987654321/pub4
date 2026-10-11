# frozen_string_literal: true

module Operator
  # The scanner takes one flock file per scanned path under .constitutional_locks
  # and never removes it, so the directory grows by a file per path forever. A
  # lock untouched for the TTL is not held by any live scan, so it can go.
  module LockSweep
    TTL_SECONDS = 24 * 60 * 60

    module_function

    def stale(dir, now: Time.now, ttl: TTL_SECONDS)
      Dir.glob(File.join(dir, "*.lock")).select do |path|
        File.file?(path) && now - File.mtime(path) > ttl
      end
    end

    # A file whose flock is taken right now belongs to a live scan whatever its
    # mtime says, so it is skipped rather than deleted from under its holder.
    def sweep(dir, apply:, now: Time.now, ttl: TTL_SECONDS)
      found = stale(dir, now:, ttl:)
      return found.size unless apply

      found.count { |path| remove_unheld(path) }
    end

    # One sweep per process, from the scanner's first lock. The scan is the only
    # writer, so sweeping where it writes keeps the directory bounded without a
    # cron job or an operator remembering `bin/cleanup --apply`.
    def sweep_once(dir, ttl: TTL_SECONDS)
      @swept ||= {}
      return 0 if @swept[dir]

      @swept[dir] = true
      sweep(dir, apply: true, ttl:)
    rescue SystemCallError
      0
    end

    def remove_unheld(path)
      File.open(path, File::RDWR) do |file|
        return false unless file.flock(File::LOCK_EX | File::LOCK_NB)

        File.delete(path)
        true
      end
    rescue Errno::ENOENT
      false
    end
  end
end
