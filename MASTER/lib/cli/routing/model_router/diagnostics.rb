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

          # The outcome feeds ProviderHealth, whose score the router routes on. A provider
          # that keeps failing is parked by Io::LaneState's skip cache, the one place every
          # "may I call this model" question asks; the separate quarantine log this once
          # wrote had no reader left, so a parked provider stayed in the pool regardless.
          def record_provider_outcome(model:, status:, latency_ms: nil, error: nil)
            return unless @provider_health

            @provider_health.record(model:, status:, latency_ms:, error:)
          rescue StandardError => e
            Master::Ground::Swallow.log(e, context: "Diagnostics.record_provider_outcome")
            nil
          end

          # @capability_map is always constructed (ModelRouter#initialize), unlike
          # @provider_health above which nothing in this codebase ever passes in —
          # so this has no equivalent guard to fall silent behind. Until today
          # nothing called it: preferred(task_type:) already checks
          # @capability_map.best_model_for(task_type) first, but with zero
          # recorded outcomes that check always fell through to the static
          # weights in data/models.yml.
          def record_capability_outcome(model:, task_type:, success:, metrics: {})
            return unless task_type

            # preferred(task_type:) passes task_type straight into
            # best_model_for with no type coercion, so the key written here
            # must match whatever form the caller used (a bare symbol in
            # every real call site) or the read side never finds it.
            @capability_map.record_outcome(model, task_type, success, metrics)
          rescue StandardError => e
            Master::Ground::Swallow.log(e, context: "Diagnostics.record_capability_outcome")
            nil
          end
        end
      end
    end
  end
end
