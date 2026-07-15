# frozen_string_literal: true

require "fileutils"
require "tempfile"

module Master
  module Ground
    # Atomic file writes using temp file + rename. Ensures data durability
    # via fsync, and optionally fsyncs the parent directory on POSIX systems
    # to commit the rename to disk.
    module AtomicWrite
      def write_atomic(path, content, fsync: true, fsync_dir: true, mode: 0o644)
        dir = File.dirname(path)
        FileUtils.mkdir_p(dir)

        temp = Tempfile.new(".master_atomic_", dir)
        temp.write(content)
        temp.flush
        temp.fsync if fsync
        temp.close

        File.chmod(mode, temp.path)
        File.rename(temp.path, path)
        fsync_directory(dir) if fsync_dir && RUBY_PLATFORM !~ /win32|mingw/
        path
      rescue StandardError
        cleanup_atomic_temp(temp)
        raise
      end

      def fsync_directory(dir)
        dir_fd = IO.sysopen(dir, File::RDONLY)
        dir_io = IO.new(dir_fd)
        dir_io.fsync
      ensure
        dir_io&.close
      end

      def cleanup_atomic_temp(temp)
        File.delete(temp.path) if temp && File.exist?(temp.path)
      rescue StandardError => e
        Master::Ground::Swallow.log(e, context: "AtomicWrite.cleanup_atomic_temp")
        nil
      end
    end
  end
end
