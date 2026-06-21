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
        return true if File.socket?(path)
        return false unless Speech.worker_executable?

        spawn_daemon(root:, path:)
        wait_for_socket(path)
      end

      def socket_path(root = Master::ROOT)
        File.join(root, ".master", "tts.sock")
      end

      def spawn_daemon(root:, path:)
        worker = File.join(root, "bin", "tts-worker")
        FileUtils.mkdir_p(File.dirname(path))
        env = { "BUNDLE_GEMFILE" => File.join(root, "Gemfile") }
        pid = Process.spawn(env, Gem.ruby, worker, "--daemon", path, chdir: root, out: log_path(root), err: log_path(root))
        Process.detach(pid)
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
    end
  end
end