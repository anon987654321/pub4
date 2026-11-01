# frozen_string_literal: true

module Master
  module Io
    # Spawn options for every child MASTER creates. The control-plane flock is
    # held by bin/master and closed on exec, and a descriptor named in
    # MASTER_PROCESS_LOCK_FD is closed here as well: media players, ffmpeg and
    # test subprocesses must never become lock holders.
    module ProcessSpawn
      module_function

      # libmalloc's stack-logging diagnostic is inherited by every child even
      # though MASTER does not use malloc stack logging. Remove the whole named
      # family at the spawn boundary, including values supplied by an explicit
      # child environment hash. A nil value tells Process.spawn to unset a key.
      def scrub_parent_environment!
        ENV.keys.each do |key|
          ENV.delete(key) if key.start_with?("MallocStackLogging")
        end
      end

      def environment(overrides = {})
        scrub_parent_environment!
        env = overrides.dup
        env.keys.each do |key|
          env[key] = nil if key.to_s.start_with?("MallocStackLogging")
        end
        env
      end

      def options(options = {})
        scrub_parent_environment!
        result = options.dup
        result[:close_others] = true unless result.key?(:close_others)
        lock_fd = ENV["MASTER_PROCESS_LOCK_FD"].to_i
        result[lock_fd] = :close if lock_fd.positive? && open_fd?(lock_fd)
        result
      end

      # A variable naming a descriptor this process no longer holds made every spawn fail with
      # EBADF, the disk check that guards each check child included. Only an open one is closed.
      def open_fd?(descriptor)
        IO.for_fd(descriptor, autoclose: false)

        true
      rescue Errno::EBADF
        false
      end
    end
  end
end
