# frozen_string_literal: true

require "fileutils"
require "time"

module MASTER
  module SingleInstance
    class AlreadyRunningError < StandardError
      attr_reader :lock_path, :owner_pid

      def initialize(lock_path:, owner_pid: nil)
        @lock_path = lock_path
        @owner_pid = owner_pid
        detail = owner_pid ? " (pid #{owner_pid})" : ""
        super("MASTER is already running#{detail}. Lock file: #{lock_path}")
      end
    end

    class LockHandle
      def initialize(io)
        @io = io
        @released = false
      end

      def release
        return if @released

        @released = true
        @io.flock(File::LOCK_UN)
        @io.close
      rescue StandardError
        nil
      end
    end

    module_function

    def acquire(lock_path:, allow_multi_env: "MASTER_ALLOW_MULTI")
      return nil if ENV[allow_multi_env] == "1"

      FileUtils.mkdir_p(File.dirname(lock_path))
      io = File.open(lock_path, File::RDWR | File::CREAT, 0o644)
      locked = io.flock(File::LOCK_EX | File::LOCK_NB)

      unless locked
        owner_pid = read_owner_pid(lock_path)
        io.close
        raise AlreadyRunningError.new(lock_path: lock_path, owner_pid: owner_pid)
      end

      io.rewind
      io.truncate(0)
      io.write("pid=#{Process.pid}\nstarted_at=#{Time.now.utc.iso8601}\n")
      io.flush

      handle = LockHandle.new(io)
      at_exit { handle.release }
      handle
    end

    def read_owner_pid(lock_path)
      raw = File.read(lock_path)
      m = raw.match(/pid=(\d+)/)
      return nil unless m

      m[1].to_i
    rescue StandardError
      nil
    end
  end
end
