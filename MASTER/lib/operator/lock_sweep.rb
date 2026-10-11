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

    def sweep(dir, apply:, now: Time.now, ttl: TTL_SECONDS)
      found = stale(dir, now:, ttl:)
      found.each { |path| File.delete(path) } if apply
      found.size
    end
  end
end
