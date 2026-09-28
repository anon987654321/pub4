# frozen_string_literal: true

module Master
  module CLI
    module Routing
      # Availability is a runtime constraint, not a provider preference. The
      # policy names the lowest useful capability we may descend to and the
      # maximum age of health evidence before a cloud lane becomes inconclusive.
      class AvailabilityPolicy
        LEVELS = %w[L0 L1 L2 L3 L4].freeze
        DEFAULTS = {
          "health_freshness_s" => 120,
          "dispatch_deadline_s" => 300,
          "ladder_floor" => {
            "interactive" => "L2",
            "batch_scan" => "L1",
          },
          "degrade" => {
            "council" => [7, 3, 1],
            "critique_rounds" => [2, 1, 0],
          },
        }.freeze

        def initialize(config: nil, root: Master::ROOT)
          @root = root
          @config = config || load_config
        end

        def health_freshness_s
          positive_integer(@config["health_freshness_s"], DEFAULTS["health_freshness_s"])
        end

        # Evidence says the current Claude CLI path needs materially more than
        # the proposed 90s ceiling on the development machine. 300s preserves
        # the measured sender bound while allowing the operator to tighten it.
        def dispatch_deadline_s
          env = ENV["MASTER_DISPATCH_DEADLINE_S"].to_s.strip
          return positive_integer(env, DEFAULTS["dispatch_deadline_s"]) unless env.empty?

          positive_integer(@config["dispatch_deadline_s"], DEFAULTS["dispatch_deadline_s"])
        end

        def ladder_floor(operation)
          floors = DEFAULTS["ladder_floor"].merge(@config.fetch("ladder_floor", {}).to_h)
          floors.fetch(operation.to_s, floors.fetch("interactive"))
        end

        def council_sizes
          Array(@config.dig("degrade", "council") || DEFAULTS.dig("degrade", "council")).filter_map do |size|
            Integer(size)
          rescue ArgumentError, TypeError
            nil
          end.select(&:positive?)
        end

        def critique_rounds
          Array(@config.dig("degrade", "critique_rounds") || DEFAULTS.dig("degrade", "critique_rounds")).filter_map do |rounds|
            Integer(rounds)
          rescue ArgumentError, TypeError
            nil
          end.select { |rounds| rounds >= 0 }
        end

        def level_for(model_id)
          id = model_id.to_s
          return "L3" if id.start_with?("web-chat:", "replicate:") || id.end_with?(":free", ":cloud", "-cloud")
          return "L2" if id.start_with?("ollama:", "local:")
          "L4"
        end

        def meets_floor?(model_id, operation: :interactive)
          LEVELS.index(level_for(model_id)) >= LEVELS.index(ladder_floor(operation))
        end

        private

        def load_config
          data = Master.load_yaml(File.join(@root, "data", "runtime.yml"), default: {}) || {}
          data["availability"].is_a?(Hash) ? data["availability"] : {}
        rescue StandardError => e
          Master::Ground::Swallow.log(e, context: "availability_policy.load_config")
          {}
        end

        def positive_integer(value, fallback)
          parsed = Integer(value)
          parsed.positive? ? parsed : fallback
        rescue ArgumentError, TypeError
          fallback
        end
      end
    end
  end
end
