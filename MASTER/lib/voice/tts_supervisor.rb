# frozen_string_literal: true

require "fileutils"
require "socket"
require "rbconfig"

module Master
  module Voice
    # Ensures Edge TTS UNIX-socket daemons are running before synthesis.
    # Pool size defaults to 2 for parallel synth; override via MASTER_TTS_POOL_SIZE.
    module TtsSupervisor
      START_TIMEOUT_S = 15
      POLL_INTERVAL_S = 0.1
      # Process.spawn merges env onto the parent; Falcon's web bundle vars must not
      # leak into tts-worker children or Bundler resolves against web/vendor/bundle.
      BUNDLE_ISOLATION_KEYS = %w[
        BUNDLE_PATH BUNDLE_BIN_PATH BUNDLE_WITHOUT BUNDLE_DEPLOYMENT
        BUNDLE_DISABLE_SHARED_GEMS BUNDLE_APP_CONFIG GEM_HOME GEM_PATH RUBYOPT
      ].freeze

      SPAWN_ENV_KEYS = %w[HOME USER PATH LANG LC_ALL].freeze

      @pool_rr = 0
      @spawn_failures = {}

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
          if wait_for_socket(path)
            @spawn_failures[index] = 0
            true
          else
            failures = (@spawn_failures[index] ||= 0) + 1
            @spawn_failures[index] = failures
            sleep [POLL_INTERVAL_S * (2**[failures - 1, 4].min), 2.0].min
            false
          end
        end
      end

      def spawn_daemon(root:, path:, index: 0)
        worker = File.join(root, "bin", "tts-worker")
        env = daemon_env(root)
        log = log_path(root, index:)
        debug_spawn_context(root:, env:, index:)
        pid = Process.spawn(
          env, Gem.ruby, worker, "--daemon", path,
          chdir: root, out: log, err: log, close_others: true
        )
        Process.detach(pid)
      end

      # TEMPORARY diagnostic — remove once the intermittent GemNotFound crash
      # (tts-worker resolving against MASTER/web's Gemfile.lock instead of
      # MASTER's own, despite daemon_env's isolation) is root-caused. Isolated
      # SSH reproduction has ruled out the script itself, the nil-env-unset
      # mechanism, and TtsJob's parallel dispatch -- this captures the exact
      # env/caller context at the moment a REAL Falcon-triggered spawn
      # happens, to compare against a manual reproduction.
      def debug_spawn_context(root:, env:, index:)
        path = File.join(root, ".master", "tts-spawn-debug.log")
        File.open(path, "a") do |f|
          f.puts("--- spawn at #{Time.now} (index=#{index}, caller pid=#{Process.pid}) ---")
          f.puts("daemon_env: #{env.inspect}")
          f.puts("caller ENV[RUBYOPT]=#{ENV["RUBYOPT"].inspect} BUNDLE_GEMFILE=#{ENV["BUNDLE_GEMFILE"].inspect} GEM_HOME=#{ENV["GEM_HOME"].inspect}")
          f.puts("Gem.ruby=#{Gem.ruby} RbConfig.ruby=#{RbConfig.ruby}")
          f.puts("caller $LOADED_FEATURES bundler entries: #{$LOADED_FEATURES.grep(/bundler/).inspect}")
        end
      rescue StandardError => e
        Kernel.warn("debug_spawn_context failed: #{e.class}: #{e.message}")
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

        UNIXSocket.open(path) do |socket|
          socket.write(%({"health":true}\n))
          ready = IO.select([socket], nil, nil, 1)
          return false unless ready

          return socket.gets.to_s.strip == "ok"
        end
      rescue SystemCallError, EOFError, IOError
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
        env = spawn_env(root).dup
        # Wipe bundle keys so child tts-worker doesn't inherit web bundle state.
        BUNDLE_ISOLATION_KEYS.each { |key| env[key] = nil }
        env
      end

      def spawn_env(root)
        {
          "HOME" => ENV.fetch("HOME", ""),
          "USER" => ENV.fetch("USER", ""),
          "PATH" => ENV.fetch("PATH", "/usr/local/bin:/usr/bin:/bin"),
          "LANG" => ENV.fetch("LANG", "C.UTF-8"),
          "LC_ALL" => ENV.fetch("LC_ALL", "C.UTF-8"),
          "BUNDLE_GEMFILE" => File.join(root, "Gemfile"),
        }
      end
    end
  end
end
