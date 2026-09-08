# frozen_string_literal: true

require "fileutils"
require "json"
require "time"
require "timeout"
require "yaml"

module Master
  module Ops
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

      def valid?
        enabled.size <= 1
      end

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
              "Set exactly one loop: MASTER_LOOP=fix|watch|watcher or MASTER_AUTOFIX=1, MASTER_WATCH=1, MASTER_WATCHER=1."
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

      def allowed_to_start?(name)
        validate_loop_slot!
        return false unless enabled?(name)
        return false if LoopOwner.active
        cooldown_elapsed?(name)
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
