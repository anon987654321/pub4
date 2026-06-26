# frozen_string_literal: true

require "fileutils"
require "socket"

module Master
  module Voice
    # Ensures Edge TTS UNIX-socket daemons are running before synthesis.
    # Pool size defaults to 2 for parallel synth; override via MASTER_TTS_POOL_SIZE.
    module TtsSupervisor
      START_TIMEOUT_S = 15
      POLL_INTERVAL_S = 0.1

      @pool_rr = 0

      module_function

      def pool_size
        ENV.fetch("MASTER_TTS_POOL_SIZE", "2").to_i.clamp(1, 4)
      end

      def ensure_daemon!(root: Master::ROOT)
        return false unless Speech.worker_executable?

        FileUtils.mkdir_p(File.join(root, ".master"))
        ok = pool_size.times.map { |i| ensure_pool_worker!(root:, index: i) }.all?
        link_legacy_socket(root)
        ok
      end

      def socket_path(root = Master::ROOT, index: 0)
        if pool_size <= 1 && index.zero?
          File.join(root, ".master", "tts.sock")
        else
          File.join(root, ".master", "tts-#{index}.sock")
        end
      end

      def next_socket(root = Master::ROOT)
        size = pool_size
        idx = @pool_rr % size
        @pool_rr += 1
        path = socket_path(root, index: idx)
        return path if socket_alive?(path)

        ensure_pool_worker!(root:, index: idx)
        path
      end

      def ensure_pool_worker!(root:, index:)
        path = socket_path(root, index:)
        return true if socket_alive?(path)

        with_daemon_lock(root, index:) do
          return true if socket_alive?(path)

          File.unlink(path) if File.exist?(path)
          spawn_daemon(root:, path:, index:)
          wait_for_socket(path)
        end
      end

      def spawn_daemon(root:, path:, index: 0)
        worker = File.join(root, "bin", "tts-worker")
        env = daemon_env(root)
        log = log_path(root, index:)
        pid = Process.spawn(
          env, Gem.ruby, worker, "--daemon", path,
          chdir: root, out: log, err: log, close_others: true
        )
        Process.detach(pid)
      end

      def link_legacy_socket(root)
        return if pool_size > 1

        legacy = File.join(root, ".master", "tts.sock")
        primary = socket_path(root, index: 0)
        return if legacy == primary || File.socket?(legacy)

        File.unlink(legacy) if File.exist?(legacy) && !File.socket?(legacy)
        File.symlink(primary, legacy) unless File.exist?(legacy)
      rescue StandardError
        nil
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

      def with_daemon_lock(root, index: 0)
        path = lock_path(root, index:)
        deadline = Time.now + START_TIMEOUT_S
        acquired = false
        until acquired = lock_directory(path)
          return false if Time.now >= deadline

          sleep POLL_INTERVAL_S
        end
        yield
      ensure
        Dir.rmdir(path) if acquired && Dir.exist?(path)
      end

      def lock_directory(path)
        Dir.mkdir(path, 0o700)
        true
      rescue Errno::EEXIST
        false
      end

      def log_path(root, index: 0)
        suffix = pool_size <= 1 && index.zero? ? "" : "-#{index}"
        File.join(root, ".master", "tts-worker#{suffix}.log")
      end

      def lock_path(root, index: 0)
        suffix = pool_size <= 1 && index.zero? ? "" : "-#{index}"
        File.join(root, ".master", "tts-worker#{suffix}.starting")
      end

      def daemon_env(root)
        env = ENV.to_h
        %w[BUNDLE_PATH BUNDLE_BIN_PATH RUBYOPT GEM_HOME GEM_PATH].each { env.delete(_1) }
        env["BUNDLE_GEMFILE"] = File.join(root, "Gemfile")
        env
      end
    end
  end
end
