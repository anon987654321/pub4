# frozen_string_literal: true

module Master
  module Now
    module Routing
      class ModelRouter
        # Failover retry/cooldown thresholds read from data/models.yml —
        # separate from ModelRouter's own model-selection/escalation logic.
        module FailoverConfig
          def failover_max_retries
            @rules.dig("failover", "max_retries").to_i
          end

          def failover_cooldown_seconds
            val = @rules.dig("failover", "cooldown_seconds").to_i
            val.positive? ? val : 300
          end

          def failover_cooldown_tiers
            tiers = Array(@rules.dig("failover", "cooldown_tiers")).map(&:to_i).select(&:positive?)
            tiers.empty? ? [30, 60, failover_cooldown_seconds] : tiers
          end

          def failover_skip_ttl_ms
            Ground::ModelSkipCache.skip_ttl_ms
          end
        end
      end
    end
  end
end
