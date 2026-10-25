# frozen_string_literal: true

require "fileutils"

module Master
  module Boot
    # Stale Bundler stores are moved aside rather than deleted during native-ABI
    # recovery. Bound their later disk usage without ever following a symlink or
    # touching the active `gems` store. Cleanup is age-gated and dry-run by default.
    module StaleBundleSweep
      TTL_SECONDS = 30 * 24 * 60 * 60
      STORE_NAME = /\Agems\.stale-\d+-\d+(?:-\d+)?\z/.freeze
      STALE_TIMESTAMP = /\Agems\.stale-\d+-(\d+)(?:-\d+)?\z/.freeze

      module_function

      def candidates(root, now: Time.now, ttl: TTL_SECONDS)
        base = File.expand_path(root)
        return [] unless File.directory?(base) && !File.symlink?(base)

        Dir.glob(File.join(base, "*", "gems.stale-*")).select do |path|
          eligible?(path, root: base, now:, ttl:)
        end
      rescue SystemCallError
        []
      end

      # Returns the number of eligible stores observed. With apply: false this
      # is a report-only census; deletion requires the caller's explicit consent.
      def sweep(root, apply: false, now: Time.now, ttl: TTL_SECONDS)
        found = candidates(root, now:, ttl:)
        return found.size unless apply

        found.count do |path|
          next false unless eligible?(path, root: File.expand_path(root), now:, ttl:)

          FileUtils.rm_rf(path)
          !File.exist?(path) && !File.symlink?(path)
        rescue SystemCallError
          false
        end
      end

      def eligible?(path, root:, now:, ttl:)
        candidate = File.expand_path(path)
        base = File.expand_path(root)
        parent = File.dirname(candidate)

        # The only authorized target shape is
        # ~/.master/bundler/<store-key>/gems.stale-<pid>-<timestamp>[-n].
        return false unless File.dirname(parent) == base
        return false if File.symlink?(base) || File.symlink?(parent) || File.symlink?(candidate)
        return false unless File.directory?(parent) && File.directory?(candidate)
        return false unless File.basename(candidate).match?(STORE_NAME)

        renamed_at = File.basename(candidate)[STALE_TIMESTAMP, 1]
        return false unless renamed_at

        # The directory's mtime reflects the old gem store, not when it was
        # renamed out of service. Use the embedded rename timestamp so a newly
        # quarantined store gets its full retention TTL.
        now.to_f - renamed_at.to_i >= ttl
      rescue Errno::ENOENT, Errno::EACCES
        false
      end
      private_class_method :eligible?
    end
  end
end
