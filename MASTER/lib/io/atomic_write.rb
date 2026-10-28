# frozen_string_literal: true

require "fileutils"
require "tempfile"

module Master
  module Io
    # Atomic file writes using temp file + rename. Ensures data durability
    # via fsync, and optionally fsyncs the parent directory on POSIX systems
    # to commit the rename to disk.
    module AtomicWrite
      # A rewrite keeps the file's own mode unless one is asked for: the rename
      # replaced it with 0644, and an executable rewritten here stopped being one.
      # The bytes go out as given. bin/master sets Encoding.default_internal, so a
      # text-mode temp file transcoded on write, and restoring a binread
      # snapshot of any file holding a non-ASCII byte raised mid-rollback.
      # Resolve only the top-level system aliases (for example /tmp -> /private/tmp
      # on macOS). A symlink below that anchor is a caller-controlled path
      # substitution and must be refused before mkdir_p can create outside it.
      private def verified_atomic_directory(path)
        expanded = File.expand_path(path)
        components = expanded.split(File::SEPARATOR).reject(&:empty?)
        current = File::SEPARATOR

        components.each do |component|
          candidate = File.join(current, component)
          unless File.exist?(candidate) || File.symlink?(candidate)
            current = candidate
            next
          end

          stat = File.lstat(candidate)
          if stat.symlink?
            unless File.dirname(candidate) == File::SEPARATOR
              raise IOError, "refusing symlinked atomic-write directory component"
            end

            resolved = File.realpath(candidate)
            resolved_stat = File.lstat(resolved)
            unless resolved_stat.directory? && !resolved_stat.symlink?
              raise IOError, "atomic-write root alias does not resolve to a directory"
            end
            current = resolved
          else
            raise IOError, "atomic-write parent component is not a directory" unless stat.directory?

            current = candidate
          end
        end

        current
      rescue SystemCallError => error
        raise IOError, "cannot safely resolve atomic-write directory: #{error.class}: #{error.message}"
      end

      def write_atomic(path, content, fsync: true, fsync_dir: true, mode: nil)
        expanded_destination = File.expand_path(path)
        dir = verified_atomic_directory(File.dirname(expanded_destination))
        destination = File.join(dir, File.basename(expanded_destination))

        FileUtils.mkdir_p(dir)
        directory_stat = File.lstat(dir)
        unless directory_stat.directory? && !directory_stat.symlink?
          raise IOError, "atomic-write parent is not a real directory"
        end
        raise IOError, "atomic-write parent changed during creation" unless verified_atomic_directory(dir) == dir

        original_stat = if File.exist?(destination) || File.symlink?(destination)
                          stat = File.lstat(destination)
                          unless stat.file? && !stat.symlink? && stat.nlink == 1
                            raise IOError, "atomic-write destination must be a singly linked regular file"
                          end
                          stat
                        end
        mode ||= original_stat ? original_stat.mode & 0o7777 : 0o644

        temp = Tempfile.new(".master_atomic_", dir, binmode: true)
        current_directory = File.lstat(dir)
        unless current_directory.directory? && !current_directory.symlink? &&
               current_directory.dev == directory_stat.dev && current_directory.ino == directory_stat.ino &&
               verified_atomic_directory(dir) == dir
          raise IOError, "atomic-write directory changed while opening temp file"
        end

        temp.write(content)
        temp.flush
        temp.fsync if fsync
        temp.chmod(mode)
        temp.close

        # Detect replacement of the parent or destination before rename. The
        # rename never follows a destination symlink, but a replaced parent
        # could redirect the temp-file move outside the directory we opened.
        current_directory = File.lstat(dir)
        unless current_directory.directory? && !current_directory.symlink? &&
               current_directory.dev == directory_stat.dev && current_directory.ino == directory_stat.ino &&
               verified_atomic_directory(dir) == dir
          raise IOError, "atomic-write directory changed before rename"
        end
        current_destination = if File.exist?(destination) || File.symlink?(destination)
                                File.lstat(destination)
                              end
        if original_stat
          unless current_destination&.file? && !current_destination.symlink? &&
                 current_destination.nlink == 1 &&
                 current_destination.dev == original_stat.dev && current_destination.ino == original_stat.ino
            raise IOError, "atomic-write destination changed before rename"
          end
        elsif current_destination
          raise IOError, "atomic-write destination appeared before rename"
        end

        File.rename(temp.path, destination)
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
        return unless temp

        temp.close unless temp.closed?
        File.delete(temp.path) if File.exist?(temp.path) || File.symlink?(temp.path)
        nil
      rescue StandardError => e
        Master::Ground::Swallow.log(e, context: "AtomicWrite.cleanup_atomic_temp")
        nil
      end
    end
  end
end
