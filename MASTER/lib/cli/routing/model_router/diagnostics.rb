# frozen_string_literal: true

module Master
  module CLI
    module Routing
      class ModelRouter
        # Score reporting, provider-outcome recording, and runtime-registry
        # lookup — separate from ModelRouter's own model-selection logic.
        module Diagnostics
          def score_breakdown(task_type: :exploration)
            return [] unless enabled?
            candidates = @rules.dig("models", current_tier(task_type:)).to_a
            weights = @rules.fetch("weights", {})
            qw = [weights.fetch("quality", 1.0).to_f, 0.01].max
            sw = [weights.fetch("speed", 1.0).to_f, 0.01].max
            cw = [weights.fetch("cost", 1.0).to_f, 0.01].max
            candidates.map do |m|
              s = m["score"] || {}
              q = s.fetch("quality", 0.5).to_f * qw
              sp = [s.fetch("speed", 1.0).to_f * sw, 0.01].max
              co = [s.fetch("cost", 0.5).to_f * cw, 0.001].max
              { id: m["id"], q:, s: sp, c: co, total: q * sp * co }
            end.sort_by { |x| -x[:total] }
          end

          def record_provider_outcome(model:, status:, latency_ms: nil, error: nil)
            @provider_health&.record(model:, status:, latency_ms:, error:)
          rescue StandardError => e
            Master::Ground::Swallow.log(e, context: "Diagnostics.record_provider_outcome")
            nil
          end

          def runtime_choice(task: :exploration)
            Master::Ground::RuntimeRegistry.new.choose(task:)
          rescue StandardError
            { provider: :local, model: preferred, score: 0.5, quarantined: [] }
          end
        end
      end
    end
  end
end
