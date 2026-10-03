# frozen_string_literal: true

require "fileutils"
require "json"
require "open3"
require "time"
require "socket"
require "timeout"
require "yaml"

module Master
  module Ops
    module ProcessLock
      PATH = File.join(Master::ROOT, ".master", "process.lock").freeze

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
              at: Time.now.utc.iso8601
            ))
            io.write("\n")
            io.flush
            io.fsync
            return io
          end

          io.close
          return nil unless attempts.zero? && reclaimable?(path)

          attempts += 1
        end
      rescue StandardError
        io&.close
        raise
      end

      MEDIA_PLAYER_COMMAND = %r{(?:/|\\)(?:STUDIO\/dilla)/(?:liveset|royksopp)\.rb(?:\s|$)}.freeze

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

        out, status = Open3.capture2("ps", "-ax", "-o", "pid=,ppid=,pgid=,command=")
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

      def read_metadata(path)
        return {} unless File.file?(path)

        JSON.parse(File.read(path))
      rescue JSON::ParserError, SystemCallError
        {}
      end

      # On a locked file, metadata can lag the real process after a crash/restart.
      # lsof is advisory for owner reporting; stale-lock recovery probes the OS
      # flock directly, so recovery does not depend on an external process listing.
      def lock_holders(path)
        lsof = ["/usr/sbin/lsof", "/usr/bin/lsof", "lsof"].find do |candidate|
          candidate == "lsof" || File.executable?(candidate)
        end
        return nil unless lsof

        out, status = Open3.capture2(lsof, "-t", path)
        return nil unless status.success? || status.exitstatus == 1

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
    end

    module LoopOwner
      DIR = File.join(Master::ROOT, ".master", "active_loop").freeze
      INFO = File.join(DIR, "owner.json").freeze
      STALE_SECONDS = 3600

      module_function

      def claim(name)
        cleanup_stale!
        FileUtils.mkdir_p(File.dirname(DIR))
        Dir.mkdir(DIR)
        File.write(INFO, JSON.generate(loop: name.to_s, pid: Process.pid, at: Time.now.utc.iso8601))
        true
      rescue Errno::EEXIST => e
        Master::Ground::Swallow.log(e, context: "LoopOwner.claim")
        false
      end

      def release
        FileUtils.rm_rf(DIR) if Dir.exist?(DIR)
      end

      def active
        cleanup_stale!
        return unless File.exist?(INFO)

        JSON.parse(File.read(INFO))
      rescue StandardError
        { "loop" => "unknown" }
      end

      def cleanup_stale!
        return unless File.exist?(INFO)

        data = JSON.parse(File.read(INFO))
        pid = data["pid"].to_i
        at = Time.iso8601(data["at"].to_s) rescue Time.at(0)
        stale = pid <= 0 || !process_alive?(pid) || (Time.now.utc - at) > STALE_SECONDS
        release if stale
      rescue StandardError
        release
      end

      def process_alive?(pid)
        Process.kill(0, pid)
        true
      rescue Errno::ESRCH => e
        Master::Ground::Swallow.log(e, context: "LoopOwner.process_alive?")
        false
      rescue Errno::EPERM
        true
      end

      def with_claim(name)
        return false unless claim(name)

        yield
      ensure
        release
      end
    end

    # At most one *slot* loop (autofix/watch/watcher) may run at a time. The loops
    # and their env flags are not defined here — they come from the single source,
    # data/limits.yml#process, via ProcessBudget. LoopSlot is only the mutual-exclusion
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
      CONFIG_PATH = File.join(Master::ROOT, "data", "limits.yml").freeze
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
