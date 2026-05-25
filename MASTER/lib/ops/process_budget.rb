# frozen_string_literal: true

require "timeout"
require "yaml"

module Master
  module Ops
    module ProcessBudget
      CONFIG_PATH = File.join(Master::ROOT, "data", "ops", "process.yml").freeze
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
        YAML.safe_load_file(CONFIG_PATH, aliases: true) || {}
      rescue StandardError
        {}
      end

      def loop_config(name)
        config.fetch("loops", {}).fetch(name.to_s, {})
      end

      def loop_names
        config.fetch("loops", {}).keys.sort
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
          active_loops: active_loops,
          max_active_loops: max_active_loops,
          loops: loop_names.to_h { |name| [name, loop_status(name)] }
        }
      end

      def loop_status(name)
        spec = loop_config(name)
        env = spec["env"]
        {
          enabled: enabled?(name),
          slot: slot_loop?(name, spec),
          env: env,
          env_value: env ? ENV.fetch(env, "0") : nil,
          cooldown_elapsed: cooldown_elapsed?(name),
          max_run_seconds: spec["max_run_seconds"].to_i,
          min_sleep_seconds: spec["min_sleep_seconds"].to_i
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
        return :cooldown unless cooldown_elapsed?(name)

        mark!(name)
        seconds = loop_config(name)["max_run_seconds"].to_i
        seconds.positive? ? Timeout.timeout(seconds) { yield } : yield
      rescue Timeout::Error
        :timeout
      end
    end
  end
end
