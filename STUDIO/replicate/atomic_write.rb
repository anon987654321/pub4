# frozen_string_literal: true

require "fileutils"
require "json"
require "tempfile"

module Studio
  module AtomicWrite
    def write_atomic(path, content)
      directory = File.dirname(path)
      FileUtils.mkdir_p(directory)
      mode = File.file?(path) ? File.stat(path).mode & 0o7777 : 0o640
      Tempfile.create(["studio-", ".tmp"], directory, binmode: true) do |tmp|
        tmp.write(content.to_s)
        tmp.flush
        tmp.fsync
        tmp.close
        File.chmod(mode, tmp.path)
        File.rename(tmp.path, path)
      end
      path
    end

    # Stream a large artifact through a same-directory temporary before publish.
    # This keeps content-addressed blobs safe without loading the whole image
    # into memory, and a failed copy never replaces a previously valid artifact.
    def copy_atomic(source, destination)
      target = File.expand_path(destination)
      directory = File.dirname(target)
      FileUtils.mkdir_p(directory)
      mode = File.file?(target) ? File.stat(target).mode & 0o7777 : 0o640
      Tempfile.create(["studio-copy-", ".tmp"], directory, binmode: true) do |tmp|
        File.open(source, "rb") { |input| IO.copy_stream(input, tmp) }
        tmp.flush
        tmp.fsync
        tmp.close
        File.chmod(mode, tmp.path)
        File.rename(tmp.path, target)
      end
      destination
    end

    # Serialize cooperating writers and publish each complete JSONL record under
    # the lock. A process that died mid-write can leave an unterminated final
    # fragment; discard that fragment before the next append instead of making
    # the entire manifest unreadable.
    def append_jsonl(path, value, mode: 0o640)
      FileUtils.mkdir_p(File.dirname(path))
      File.open(path, File::RDWR | File::CREAT, mode) do |file|
        file.binmode
        file.flock(File::LOCK_EX)
        begin
          truncate_incomplete_jsonl_tail(file)
          file.seek(0, IO::SEEK_END)
          payload = (JSON.generate(value) + "\n").b
          offset = 0
          while offset < payload.bytesize
            written = file.write(payload.byteslice(offset..))
            raise IOError, "JSONL append wrote no bytes" unless written&.positive?

            offset += written
          end
          file.flush
          file.fsync
        ensure
          file.flock(File::LOCK_UN)
        end
      end
      path
    end

    private

    def truncate_incomplete_jsonl_tail(file)
      file.seek(0, IO::SEEK_END)
      cursor = file.pos
      return if cursor.zero?

      file.seek(cursor - 1, IO::SEEK_SET)
      return if file.read(1) == "\n".b

      while cursor.positive?
        length = [cursor, 4096].min
        cursor -= length
        file.seek(cursor, IO::SEEK_SET)
        chunk = file.read(length)
        newline = chunk.rindex("\n".b)
        next unless newline

        file.truncate(cursor + newline + 1)
        return
      end
      file.truncate(0)
    end
  end
end
