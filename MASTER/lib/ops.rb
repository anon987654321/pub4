# frozen_string_literal: true

require "fileutils"
require "json"
require_relative "io/exec"
require "time"
require "socket"
require "timeout"
require "yaml"

module Master
  module Ops
    module ProcessLock
      module_function

      # The e2e boot tests point the lock at their own tmpdir through this
      # override, because any live process holding the real file (a tts-worker
      # inherits the lock fd) flakes a boot that would otherwise succeed.
      # Unset, every path stays the checkout's own file.
      def lock_path(root = Master::ROOT)
        ENV["MASTER_PROCESS_LOCK_PATH"] || File.join(root, ".master", "process.lock")
      end

      def acquire!(path: nil, root: Master::ROOT, mode: "master", inherit_fd: false)
        path ||= lock_path(root)
        FileUtils.mkdir_p(File.dirname(path))
        attempts = 0
        # Declared here so the rescue below closes the handle the loop opened.
        io = nil

        loop do
          io = File.open(path, File::RDWR | File::CREAT, 0o600)
          if io.flock(File::LOCK_EX | File::LOCK_NB)
            io.close_on_exec = !inherit_fd
            io.rewind
            io.truncate(0)
            io.write(JSON.generate(
              pid: Process.pid,
              host: Socket.gethostname,
              mode: mode.to_s,
              at: Time.now.utc.iso8601,
            ))
            io.write("\n")
            io.flush
            io.fsync
            return io
          end

          io.close
          return unless attempts.zero? && reclaimable?(path)

          attempts += 1
        end
      rescue StandardError
        io&.close
        raise
      end

      # A headless run queues behind whoever holds the lock instead of exiting
      # 75: on 2026-11-04 a backlog item handed to `bin/master --headless` died at
      # once because an interactive session had held the lock for 13 hours.
      # Yields the owner before each wait so the caller can say who it waits on.
      def acquire_waiting!(wait:, path: nil, root: Master::ROOT, mode: "master", poll: 5,
                           sleeper: ->(seconds) { sleep(seconds) },
                           clock: -> { Process.clock_gettime(Process::CLOCK_MONOTONIC) })
        deadline = clock.call + wait
        loop do
          lock = acquire!(path:, root:, mode:)
          return lock if lock
          return if clock.call >= deadline

          yield owner(path: path || lock_path(root)) if block_given?
          sleeper.call(poll)
        end
      end

      MEDIA_PLAYER_COMMAND = %r{(?:/|\\)STUDIO/dilla/dilla\.rb(?:\s|$)}.freeze

      def reclaimable?(path)
        probe = File.open(path, File::RDWR | File::CREAT, 0o600)
        return true if probe.flock(File::LOCK_EX | File::LOCK_NB) == true

        # The metadata PID may still be alive when it is a legacy Dilla player.
        # Inspect the real flock holders before declaring the control plane busy;
        # current media children close the lock, but old players must be reaped.
        reclaim_detached_media_holders(path)
      rescue Errno::ENOENT
        true
      rescue StandardError => e
        Master::Ground::Swallow.log(e, context: "ProcessLock.reclaimable?")
        false
      ensure
        if probe
          probe.flock(File::LOCK_UN) rescue nil
          probe.close rescue nil
        end
      end

      def reclaim_detached_media_holders(path)
        holders = lock_holders(path)
        return false if holders.nil? || holders.empty?

        out, status = Io::Exec.capture2("ps", "-ax", "-o", "pid=,ppid=,pgid=,command=", timeout: Io::Exec::DEFAULT_TIMEOUT)
        return false unless status.success?

        rows = out.lines.filter_map do |line|
          match = line.strip.match(/\A(\d+)\s+(\d+)\s+(\d+)\s+(.+)\z/)
          next unless match

          pid, ppid, pgid = match.captures.first(3).map(&:to_i)
          { pid:, ppid:, pgid:, command: match[4] }
        end
        by_parent = rows.group_by { |row| row[:ppid] }
        roots = holders.filter_map do |pid|
          row = rows.find { |candidate| candidate[:pid] == pid }
          next unless row && row[:command].match?(MEDIA_PLAYER_COMMAND)

          row
        end.uniq { |row| row[:pid] }
        return false if roots.empty?

        victims = roots.flat_map do |root|
          descendants = []
          queue = [root[:pid]]
          until queue.empty?
            parent = queue.shift
            by_parent.fetch(parent, []).each do |child|
              next if descendants.include?(child[:pid])

              descendants << child[:pid]
              queue << child[:pid]
            end
          end
          [root[:pid], *descendants]
        end.uniq.reject { |pid| pid == Process.pid }

        victims.reverse_each { |pid| Process.kill("TERM", pid) rescue nil }
        deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + 0.25
        loop do
          probe = File.open(path, File::RDWR | File::CREAT, 0o600)
          free = probe.flock(File::LOCK_EX | File::LOCK_NB) == true
          probe.flock(File::LOCK_UN) if free
          probe.close
          return true if free
          break if Process.clock_gettime(Process::CLOCK_MONOTONIC) >= deadline
          sleep 0.025
        end
        false
      rescue StandardError => e
        Master::Ground::Swallow.log(e, context: "ProcessLock.reclaim_detached_media_holders")
        false
      end

      def process_alive?(pid)
        Process.kill(0, pid)
        true
      rescue Errno::ESRCH
        false
      rescue Errno::EPERM
        true
      end

      # On a locked file, metadata can lag the real process after a crash/restart.
      # lsof is advisory for owner reporting; stale-lock recovery probes the OS
      # flock directly, so recovery does not depend on an external process listing.
      def lock_holders(path)
        lsof = ["/usr/sbin/lsof", "/usr/bin/lsof", "lsof"].find do |candidate|
          candidate == "lsof" || File.executable?(candidate)
        end
        return unless lsof

        out, status = Io::Exec.capture2(lsof, "-t", path, timeout: Io::Exec::DEFAULT_TIMEOUT)
        return unless status.success? || status.exitstatus == 1

        out.lines.filter_map { |line| Integer(line.strip, exception: false) }.uniq.reject { |pid| pid == Process.pid }
      rescue StandardError => e
        Master::Ground::Swallow.log(e, context: "ProcessLock.lock_holders")
        nil
      end

      def release(io)
        return unless io

        io.flock(File::LOCK_UN)
        io.close
      rescue StandardError => e
        Master::Ground::Swallow.log(e, context: "ProcessLock.release")
      end

      def owner(path: lock_path)
        return {} unless File.exist?(path)

        io = File.open(path, File::RDWR)
        if io.flock(File::LOCK_EX | File::LOCK_NB)
          io.flock(File::LOCK_UN)
          return {}
        end

        io.rewind
        data = JSON.parse(io.read)
        holders = lock_holders(path)
        if holders&.any?
          data["lock_holder_pid"] = holders.first
          data["pid"] = holders.first unless process_alive?(data["pid"].to_i)
        elsif !process_alive?(data["pid"].to_i)
          data["stale"] = true
        end
        data
      rescue JSON::ParserError, SystemCallError
        {}
      ensure
        io&.close
      end

      # One frame of who owns the control plane, for `bin/master --status`: the
      # lock holder, its mode, how long it has held the lock, and how long the
      # session transcript has been quiet — the last-activity signal an
      # operator reads before deciding to wait or to look for the holder's
      # terminal. Read-only by construction: owner() unlocks immediately when
      # the file is free, and never writes the lock. A free lock says so in as
      # many words rather than printing an empty frame.
      def status_report(root: Master::ROOT, now: Time.now)
        holder = owner(path: lock_path(root))
        lines = []
        if holder.empty?
          lines << "master0: control plane idle - no lock holder"
        else
          lines << "master0: lock held by pid=#{holder["pid"]} host=#{holder["host"]} " \
                   "mode=#{holder["mode"]} since=#{holder["at"]}"
          held = duration_since(holder["at"], now:)
          lines << "master0: held for #{held}" if held
          lines << "master0: recorded holder is gone - metadata is stale" if holder["stale"]
        end

        idle = duration_since(session_activity(root:)&.utc&.iso8601, now:)
        lines << "master0: last session activity #{idle} ago" if idle
        lines << "master0: no session transcript yet" if idle.nil? && !holder.empty?
        lines
      end

      def duration_since(timestamp, now: Time.now)
        return unless timestamp.is_a?(String) && timestamp.match?(/\A\d{4}-/)

        seconds = now - Time.iso8601(timestamp)
        return "under a second" if seconds < 1

        whole = seconds.to_i
        hours = whole / 3600
        minutes = (whole % 3600) / 60
        rest = whole % 60
        case
        when hours.positive? then "#{hours}h #{minutes}m"
        when minutes.positive? then "#{minutes}m #{rest}s"
        else "#{rest}s"
        end
      rescue ArgumentError
        nil
      end

      # The CLI transcript is the holder's own record of what it is doing; its
      # mtime is the honest idle signal. The lock's `since` says when the
      # holder acquired, not when it last did anything.
      def session_activity(root: Master::ROOT)
        path = File.join(root, ".master", "session.json")
        File.mtime(path) if File.readable?(path)
      rescue StandardError
        nil
      end
    end

    # At most one *slot* loop (autofix/watch/watcher) may run at a time. The loops
    # and their env flags are not defined here — they come from the single source,
    # data/budgets.yml#process, via ProcessBudget. LoopSlot is only the mutual-exclusion
    # view over the slot loops; the background heartbeat is non-slot and excluded.
    module LoopSlot
      module_function

      def flags
        ProcessBudget.env_by_loop.select { |name, _env| ProcessBudget.slot_loop?(name) }
      end

      def enabled
        ProcessBudget.active_loops
      end

      def selected
        enabled.first
      end

      def valid? = ProcessBudget.valid_loop_slot?

      def status
        {
          selected:,
          enabled:,
          valid: valid?,
          flags: flags.transform_values { |env| ENV.fetch(env, "0") },
        }
      end

      def validate!
        return true if valid?

        raise ArgumentError,
              "Too many active MASTER loops: #{enabled.join(", ")}; max=#{ProcessBudget.max_active_loops}"
      end
    end

    module ProcessBudget
      CONFIG_PATH = Master.config_path("process").freeze
      NON_SLOT_LOOPS = %w[heartbeat].freeze
      @last_run = {}

      module_function

      def config
        @config ||= load_config
      end

      def reload!
        @config = load_config
      end

      def load_config
        return {} unless File.exist?(CONFIG_PATH)
        (YAML.safe_load_file(CONFIG_PATH, aliases: true) || {}).fetch("process", {})
      rescue StandardError => e
        Master::Ground::Swallow.log(e, context: "ProcessBudget.load_config")
        {}
      end

      def loop_config(name)
        config.fetch("loops", {}).fetch(name.to_s, {})
      end

      def loop_names
        config.fetch("loops", {}).keys.sort
      end

      # The one source for loop name -> env flag. Other loop views derive from this.
      def env_by_loop
        config.fetch("loops", {}).transform_values { |spec| spec["env"] }.compact
      end

      def slot_loop?(name, spec = loop_config(name))
        return false if NON_SLOT_LOOPS.include?(name.to_s)
        spec.fetch("slot", true) != false
      end

      def active_loops
        config.fetch("loops", {}).filter_map do |name, spec|
          next unless slot_loop?(name, spec)
          env = spec["env"]
          name if env && ENV[env] == "1"
        end
      end

      def max_active_loops
        max = config.dig("defaults", "max_active_loops").to_i
        max <= 0 ? 1 : max
      end

      def valid_loop_slot?
        active_loops.size <= max_active_loops
      end

      def status
        {
          valid: valid_loop_slot?,
          active_loops:,
          max_active_loops:,
          owner: LoopOwner.active,
          loops: loop_names.to_h { |name| [name, loop_status(name)] },
        }
      end

      def compact_status
        rows = loop_names.map do |name|
          st = loop_status(name)
          format("%-10s enabled=%-5s slot=%-5s cool=%-5s max=%ss sleep=%ss",
                 name, st[:enabled], st[:slot], st[:cooldown_elapsed],
                 st[:max_run_seconds], st[:min_sleep_seconds])
        end
        head = valid_loop_slot? ? "ok: process" : "warn: process"
        owner = LoopOwner.active
        owner_text = owner ? " owner=#{owner.fetch("loop", "unknown")}" : " owner=none"
        (["#{head}: active=#{active_loops.join(',').empty? ? 'none' : active_loops.join(',')} max=#{max_active_loops}#{owner_text}"] + rows).join("\n")
      end

      def loop_status(name)
        spec = loop_config(name)
        env = spec["env"]
        {
          enabled: enabled?(name),
          slot: slot_loop?(name, spec),
          env:,
          env_value: env ? ENV.fetch(env, "0") : nil,
          cooldown_elapsed: cooldown_elapsed?(name),
          max_run_seconds: spec["max_run_seconds"].to_i,
          min_sleep_seconds: spec["min_sleep_seconds"].to_i,
        }
      end

      def validate_loop_slot!
        return true if valid_loop_slot?

        raise ArgumentError, "too many active MASTER loops: #{active_loops.join(', ')}; max=#{max_active_loops}"
      end

      def enabled?(name)
        env = loop_config(name)["env"]
        env && ENV[env] == "1"
      end

      def cooldown_elapsed?(name)
        cooldown = loop_config(name)["min_sleep_seconds"].to_i
        return true if cooldown <= 0
        last = @last_run[name.to_s]
        last.nil? || (Time.now - last) >= cooldown
      end

      def mark!(name)
        @last_run[name.to_s] = Time.now
      end

      def run(name)
        validate_loop_slot!
        return :disabled unless enabled?(name)
        return :busy if LoopOwner.active
        return :cooldown unless cooldown_elapsed?(name)

        mark!(name)
        seconds = loop_config(name)["max_run_seconds"].to_i
        LoopOwner.with_claim(name) do
          seconds.positive? ? Timeout.timeout(seconds) { yield } : yield
        end || :busy
      rescue Timeout::Error
        :timeout
      end
    end

    module RuntimeLoopGuards
      module_function

      # Three long-running loops, each behind its own switch. The guard is one
      # move — alias the real entry point, then refuse to reach it unless the
      # environment asks for the loop — so what separates the three is data:
      # the class, the entry point, and the switch.
      GUARDS = {
        "Master::Fix::Heartbeat" => [:start!, "MASTER_HEARTBEAT"],
        "Master::Fix::Watcher" => [:run_forever, "MASTER_WATCHER"],
        "Master::Fix::WatchLoop" => [:run, "MASTER_WATCH"],
      }.freeze

      def install!
        GUARDS.each { |name, (entry, switch)| guard(name, entry, switch) }
        true
      end

      def guard_subprocess_context!
        if defined?(Falcon) && Fiber.scheduler
          raise Master::SecurityError,
                "Process.fork inside Falcon fibers induces closing scheduler panics. Shell out via Open3 or exe workers."
        end
        true
      end

      def guard(name, entry, switch)
        return unless Object.const_defined?(name)

        klass = Object.const_get(name)
        unguarded = :"#{entry.to_s.delete_suffix("!")}_without_runtime_guard!"
        return if klass.method_defined?(unguarded)

        klass.class_eval do
          alias_method unguarded, entry
          define_method(entry) do |*args, **kwargs, &block|
            return unless ENV[switch] == "1"

            send(unguarded, *args, **kwargs, &block)
          end
        end
      end
    end
  end
end
