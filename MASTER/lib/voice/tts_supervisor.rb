# frozen_string_literal: true

require "fileutils"
require "socket"

module Master
  module Voice
    # Ensures the Edge TTS UNIX-socket daemon is running before synthesis.
    module TtsSupervisor
      START_TIMEOUT_S = 5
      POLL_INTERVAL_S = 0.1

      module_function

      def ensure_daemon!(root: Master::ROOT)
        path = socket_path(root)
        return true if socket_alive?(path)
        return false unless Speech.worker_executable?

        FileUtils.mkdir_p(File.dirname(path))
        File.open(lock_path(root), File::RDWR | File::CREAT, 0o600) do |lock|
          lock.flock(File::LOCK_EX)
          return true if socket_alive?(path)

          File.unlink(path) if File.exist?(path)
          spawn_daemon(root:, path:)
          wait_for_socket(path)
        end
      end

      def socket_path(root = Master::ROOT)
        File.join(root, ".master", "tts.sock")
      end

      def spawn_daemon(root:, path:)
        worker = File.join(root, "bin", "tts-worker")
        env = { "BUNDLE_GEMFILE" => File.join(root, "Gemfile") }
        pid = Process.spawn(
          env, Gem.ruby, worker, "--daemon", path,
          chdir: root, out: log_path(root), err: log_path(root), close_others: true
        )
        Process.detach(pid)
      end

      def socket_alive?(path)
        return false unless File.socket?(path)

        UNIXSocket.open(path, &:close)
        true
      rescue SystemCallError
        false
      end

      def wait_for_socket(path)
        deadline = Time.now + START_TIMEOUT_S
        while Time.now < deadline
          return true if File.socket?(path)

          sleep POLL_INTERVAL_S
        end
        false
      end

      def log_path(root)
        File.join(root, ".master", "tts-worker.log")
      end

      def lock_path(root)
        File.join(root, ".master", "tts-worker.lock")
      end
    end
  end
end
