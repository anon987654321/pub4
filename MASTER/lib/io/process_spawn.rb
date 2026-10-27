# frozen_string_literal: true

module Master
  module Io
    # Spawn options for every child MASTER creates. The control-plane flock is
    # held by bin/master and closed on exec, and a descriptor named in
    # MASTER_PROCESS_LOCK_FD is closed here as well: media players, ffmpeg and
    # test subprocesses must never become lock holders.
    module ProcessSpawn
      module_function

      def options(options = {})
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
