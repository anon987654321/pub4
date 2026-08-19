# frozen_string_literal: true

require "timeout"
require "yaml"
require_relative "loop_owner"

module Master
  module Ops
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
  end
end
