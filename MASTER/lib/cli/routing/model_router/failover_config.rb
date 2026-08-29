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

          def failover_skip_ttl_ms
            Ground::ModelSkipCache.skip_ttl_ms
          end

          # Categories that stop retrying a model and move on. nil when unconfigured,
          # so the caller supplies its own default rather than this file naming a
          # constant from lib/review and depending on its load order. See TODO.md,
          # Inert law and config, for why fallback_policy had no reader.
          def failover_skip_categories
            configured = Array(@rules.dig("fallback_policy", "on"))
                         .map { |name| name.to_s.strip }
                         .reject(&:empty?)
                         .map(&:to_sym)
            configured.empty? ? nil : configured.freeze
          end

          # The claude_code chain's head — the subscription-billed CLI lane the
          # single-shot doors (Agent#ask, #ask_once) hop to on a category a
          # retry cannot cure. Retiring the lane in models.yml retires the hop.
          def single_call_fallback_model
            Array(@rules.dig("models", "claude_code")).first&.fetch("id", nil)
          end
        end
      end
    end
  end
end
