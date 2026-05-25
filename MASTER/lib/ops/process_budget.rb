# frozen_string_literal: true

require "yaml"
require "timeout"

module Master
  module Ops
    module ProcessBudget
      CONFIG_PATH = File.join(Master::ROOT, "data", "ops", "process.yml").freeze
      @last_run = {}

      module_function

      def config
        @config ||= begin
          if File.exist?(CONFIG_PATH)
            YAML.safe_load_file(CONFIG_PATH, aliases: true) || {}
          else
            {}
          end
        rescue StandardError
          {}
        end
      end

      def loop_config(name)
        config.fetch("loops", {}).fetch(name.to_s, {})
      end

      def active_loops
        config.fetch("loops", {}).filter_map do |name, spec|
          env = spec["env"]
          name if env && ENV[env] == "1"
        end
      end

      def validate_loop_slot!
        max = config.dig("defaults", "max_active_loops").to_i
        max = 1 if max <= 0
        active = active_loops
        return true if active.size <= max

        raise ArgumentError, "too many active MASTER loops: #{active.join(', ')}; max=#{max}"
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
        if seconds.positive?
          Timeout.timeout(seconds) { yield }
        else
          yield
        end
      rescue Timeout::Error
        :timeout
      end
    end
  end
end
