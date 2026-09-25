# frozen_string_literal: true

module Master
  module CLI
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

          # Categories that stop retrying a model and move on. nil when unconfigured,
          # so the caller supplies its own default rather than this file naming a
          # constant from lib/review and depending on its load order. An unread key is
          # found by hand and held by a test; tools/data_reach.rb's header says why.
          def failover_skip_categories
            configured = Array(@rules.dig("fallback_policy", "on"))
                         .map { |name| name.to_s.strip }
                         .reject(&:empty?)
                         .map(&:to_sym)
            configured.empty? ? nil : configured.freeze
          end

        end
      end
    end
  end
end
