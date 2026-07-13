# frozen_string_literal: true

require "fileutils"
require "tempfile"

module Master
  module Ground
    # Atomic file writes using temp file + rename. Ensures data durability
    # via fsync, and optionally fsyncs the parent directory on POSIX systems
    # to guarantee the rename is committed to disk.
    module AtomicWrite
      def write_atomic(path, content, fsync: true, fsync_dir: true, mode: 0o644)
        dir = File.dirname(path)
        FileUtils.mkdir_p(dir)

        temp = Tempfile.new(".master_atomic_", dir)
        temp.write(content)
        temp.flush
        if fsync
          temp.fsync
        end
        temp.close

        File.chmod(mode, temp.path)
        File.rename(temp.path, path)

        if fsync_dir && RUBY_PLATFORM !~ /win32|mingw/
          begin
            dir_fd = IO.sysopen(dir, File::RDONLY)
            dir_io = IO.new(dir_fd)
            dir_io.fsync
          ensure
            dir_io&.close
          end
        end

        path
      rescue StandardError => e
        begin
          File.delete(temp.path) if temp && File.exist?(temp.path)
        rescue StandardError
          nil
        end
        raise
      end
    end
  end
end
