# frozen_string_literal: true

require "digest"
require "fileutils"
require_relative "../../operator/lock_sweep"

module Master
  module Fix
    module Scan
      # FileProcessor's per-file hold. LOCK_DIR and LOCK_TIMEOUT stay on the including class, where a
      # test can shorten the timeout.
      module FileLock
        # A file whose lock could not be had in time was not measured, which is neither a clean
        # reading nor a crash of the whole walk.
        LockTimeout = Class.new(StandardError)

        private

        # flock on a lockfile that is not deleted after use. The kernel drops the lock
        # when its holder exits, so a crashed scan frees the file at once; the files
        # themselves are swept when a day old and not held (::Operator::LockSweep).

        # Shared, because a scan only reads its file and its cache writes are a rename
        # each: held exclusive across model calls, one /fix pass kept a concurrent
        # read-only census waiting past the timeout. The sweep's exclusive probe is
        # what the hold still keeps out.
        def with_file_lock(path)
          lock_path = lock_path_for(path)
          FileUtils.mkdir_p(File.dirname(lock_path))
          ::Operator::LockSweep.sweep_once(File.dirname(lock_path))
          deadline = Time.now + self.class::LOCK_TIMEOUT

          File.open(lock_path, File::RDWR | File::CREAT, 0o600) do |file|
            until file.flock(File::LOCK_SH | File::LOCK_NB)
              raise LockTimeout, "lock timeout for #{path}" if Time.now >= deadline

              sleep 0.05
            end
            yield
          end
        end

        def lock_path_for(path)
          digest = Digest::SHA256.hexdigest(File.expand_path(path))
          File.join(Master::ROOT, self.class::LOCK_DIR, "#{digest}.lock")
        end
      end
    end
  end
end
