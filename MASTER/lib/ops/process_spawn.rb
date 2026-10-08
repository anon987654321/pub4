# frozen_string_literal: true

module Master
  module Ops
    # Spawn options for every child MASTER creates. The control-plane flock is
    # intentionally inherited only across the single bin/master -> bin/cli exec;
    # media players, ffmpeg and test subprocesses must never become lock holders.
    module ProcessSpawn
      module_function

      def options(options = {})
        result = options.dup
        result[:close_others] = true unless result.key?(:close_others)
        lock_fd = ENV["MASTER_PROCESS_LOCK_FD"].to_i
        result[lock_fd] = :close if lock_fd.positive?
        result
      end
    end
  end
end
