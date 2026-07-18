# frozen_string_literal: true

module Master
  module CLI
    module Routing
      class ModelRouter
        # Uncertainty-triggered model escalation (stronger tier when a
        # response reads as low-confidence) — separate from ModelRouter's own
        # provider-availability and failover-config concerns.
        module Escalation
          def escalate?(response, threshold: DEFAULT_THRESHOLD)
            return false unless @rules.dig("routing", "escalation_enabled")

            text = response.to_s.downcase
            hits = UNCERTAINTY_PHRASES.count { |p| text.include?(p) }
            hits.to_f / UNCERTAINTY_PHRASES.size >= threshold
          end

          def stronger_model(task_type: :exploration)
            tier = @rules.dig("routing", "escalation_tier") || "strong"
            candidates = @rules.dig("models", tier).to_a
            return preferred(task_type:) if candidates.empty?

            healthy(candidates).max_by { |m| effective_score(m) }&.dig("id") || preferred(task_type:)
          end

          def escalate_if_low_confidence(response, current_model:, task_type: :exploration)
            return unless escalate?(response)

            strong_model = stronger_model(task_type:)
            return if current_model == strong_model

            strong_model
          end

          def tier_for_model(model_id)
            @rules.fetch("models", {}).each do |tier, models|
              return tier if models.is_a?(Array) && models.any? { |m| m["id"] == model_id }
            end
            "cheap"
          end

          def next_escalation_tier(current_tier)
            tier_index = ESCALATION_CHAIN.index(current_tier.to_s)
            return unless tier_index

            ESCALATION_CHAIN[tier_index + 1]
          end

          def confidence_threshold(task_type: :exploration)
            route = @rules.dig("routes", task_type.to_s)
            return DEFAULT_THRESHOLD unless route.is_a?(Hash)

            route.fetch("confidence_threshold", DEFAULT_THRESHOLD).to_f
          end

          def current_tier(task_type: :exploration)
            @rules.dig("routes", task_type.to_s) || @rules.dig("routes", "fallback_default") || "cheap"
          end
        end
      end
    end
  end
end
