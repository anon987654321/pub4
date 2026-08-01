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
      # RUBYLIB and BUNDLE_LOCKFILE were the actual live leak (confirmed on vm23):
      # RUBYLIB prepends web/vendor/bundle/.../bundler-4.0.7/lib to $LOAD_PATH before
      # any script code runs, so that vendored bundler loads regardless of GEM_HOME;
      # BUNDLE_LOCKFILE then points it at web/Gemfile.lock while BUNDLE_GEMFILE (set
      # below) correctly points at MASTER's own Gemfile -- Bundler resolves the
      # mismatched lockfile's exact gem versions against MASTER's gem set and finds
      # them missing (Bundler::GemNotFound), on every single spawn, not only some.
      BUNDLE_ISOLATION_KEYS = %w[
        BUNDLE_PATH BUNDLE_BIN_PATH BUNDLE_WITHOUT BUNDLE_DEPLOYMENT
        BUNDLE_DISABLE_SHARED_GEMS BUNDLE_APP_CONFIG BUNDLE_LOCKFILE
        GEM_HOME GEM_PATH RUBYOPT RUBYLIB
      ].freeze

      SPAWN_ENV_KEYS = %w[HOME USER PATH LANG LC_ALL].freeze

      @pool_rr = 0
      @spawn_failures = {}
      # pid of the daemon this process last spawned for each pool slot, so a
      # replacement can retire its predecessor instead of orphaning it.
      @daemon_pids = {}
      @busy_strikes = {}

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
        if socket_alive?(path)
          @busy_strikes[index] = 0
          return true
        end

        with_daemon_lock(root, index:) do
          return true if socket_alive?(path)
          return true if busy_not_dead?(path, index)

          # Unlinking the socket without retiring its owner is how this leaked:
          # the old daemon keeps running on a path nothing can reach any more,
          # and nothing ever collects it. Measured on vm23 2026-08-01 — 21 live
          # tts-workers holding 309 MB of a 1007 MB box, one more every minute.
          #
          # The trigger is that a worker is single-threaded, so one that is
          # mid-synthesis cannot answer socket_alive?'s health ping inside its
          # 1s budget. Busy reads as dead, and each false verdict spawned a
          # replacement: more workers, more load, more timeouts, more workers.
          # That climbing memory is what shed amber/bsdports, and the cold start
          # it forced on nearly every request is what made speech slow.
          retire_daemon(index)
          File.unlink(path) if File.exist?(path)
          spawn_daemon(root:, path:, index:)
          if wait_for_socket(path)
            @spawn_failures[index] = 0
            @busy_strikes[index] = 0
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
        pid = Process.spawn(
          env, Gem.ruby, worker, "--daemon", path,
          chdir: root, out: log, err: log, close_others: true
        )
        Process.detach(pid)
        @daemon_pids[index] = pid
      end

      # A worker that is synthesising cannot answer a health ping, because it is
      # single-threaded — so a failed probe means "busy" at least as often as it
      # means "dead", and synthesis can legitimately run 10-20s on this box.
      # Replacing a busy worker throws away the request it is working on and
      # forces the next one to pay a cold Ruby+Bundler+EventMachine start, which
      # is the difference between speech arriving in ~2s and in ~20s.
      #
      # So while our own daemon is still running and its socket is still on
      # disk, treat the slot as occupied and let the caller queue on the socket.
      # Only after BUSY_STRIKES consecutive silent probes do we conclude it is
      # genuinely wedged and replace it.
      BUSY_STRIKES = 3

      def busy_not_dead?(path, index)
        pid = @daemon_pids[index]
        return false unless pid && process_alive?(pid) && File.socket?(path)

        strikes = (@busy_strikes[index] ||= 0) + 1
        @busy_strikes[index] = strikes
        return false if strikes >= BUSY_STRIKES

        true
      end

      # Stop the daemon this process started for `index`, if it is still around.
      # Only ever touches a pid we spawned ourselves — never sweeps by process
      # name, so a worker belonging to another MASTER process is left alone.
      def retire_daemon(index)
        pid = @daemon_pids[index]
        return if pid.nil?

        @daemon_pids.delete(index)
        Process.kill("TERM", pid)
        # It is mid-synthesis often enough to be worth a moment; the caller
        # retries, and a stuck one must not survive as a memory leak.
        20.times do
          break if Process.waitpid(pid, Process::WNOHANG)

          sleep POLL_INTERVAL_S
        end
        Process.kill("KILL", pid) if process_alive?(pid)
      rescue Errno::ESRCH, Errno::ECHILD
        nil
      rescue StandardError => e
        Master::Ground::Swallow.log(e, context: "TtsSupervisor.retire_daemon")
        nil
      end

      def process_alive?(pid)
        Process.kill(0, pid)
        true
      rescue Errno::ESRCH, Errno::EPERM
        false
      end

      def link_legacy_socket(root)
        return if pool_size > 1

        legacy = File.join(root, ".master", "tts.sock")
        primary = socket_path(root, index: 0)
        return if legacy == primary || File.socket?(legacy)

        File.unlink(legacy) if File.exist?(legacy) && !File.socket?(legacy)
        File.symlink(primary, legacy) unless File.exist?(legacy)
      rescue StandardError => e
        Master::Ground::Swallow.log(e, context: "TtsSupervisor.link_legacy_socket")
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
      rescue SystemCallError, EOFError, IOError => e
        Master::Ground::Swallow.log(e, context: "TtsSupervisor.socket_alive?")
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
      rescue Errno::EEXIST => e
        Master::Ground::Swallow.log(e, context: "TtsSupervisor.lock_directory")
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
          # A hardcoded system PATH, not ENV.fetch("PATH", ...) -- Falcon's own PATH
          # (inherited otherwise, since this key is always present) puts web's
          # vendor/bundle/bin ahead of system bins, the same class of leak as
          # RUBYLIB/BUNDLE_LOCKFILE above.
          "PATH" => "/usr/local/bin:/usr/bin:/bin",
          "LANG" => ENV.fetch("LANG", "C.UTF-8"),
          "LC_ALL" => ENV.fetch("LC_ALL", "C.UTF-8"),
          "BUNDLE_GEMFILE" => File.join(root, "Gemfile"),
        }
      end
    end
  end
end
