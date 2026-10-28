# frozen_string_literal: true

require_relative "state"

module Master
  module Cognition
    # Explicit, revisable beliefs about MASTER itself.
    #
    # `phenomenal_consciousness` is "unknown" and stays that way. It is a
    # capability entry rather than a comment because soul.yml's anti_simulation
    # section forbids claiming what has not been shown, and the honest answer to
    # this one cannot be reached by running more code.
    class SelfModel
      MAX_BELIEFS = 32
      MAX_PERFORMANCE_BUCKETS = State::MAX_PERFORMANCE_BUCKETS
      MIN_POSTURE_ATTEMPTS = 5
      MIN_POSTURE_CALIBRATION_SAMPLES = 5
      ADVERSARIAL_ACCURACY_THRESHOLD = 0.6
      ENSEMBLE_ACCURACY_THRESHOLD = 0.85
      ADVERSARIAL_BRIER_THRESHOLD = 0.25
      ENSEMBLE_BRIER_THRESHOLD = 0.15

      CAPABILITIES = {
        "persistent_memory" => true,
        "event_recurrence" => true,
        "self_reflection" => true,
        "constitutional_governance" => true,
        "phenomenal_consciousness" => "unknown",
      }.freeze

      def update!(model, event:, payload:, salience:)
        key = "event/#{event}"
        model[key] = {
          "salience" => salience.round(4),
          "count" => model.dig(key, "count").to_i + 1,
          "last_at" => Time.now.to_i,
        }
        model["capabilities"] ||= CAPABILITIES.dup
        model["last_event"] = event.to_s
        model["last_payload"] = summarize(payload)
        record_performance!(model, payload)
        prune!(model)
        model
      end

      # Return outcome statistics only when observed labels exist. Accuracy is
      # based on actual outcomes; calibration is reported only for explicit,
      # bounded predicted-confidence values explicitly supplied before an outcome.
      def performance(model, capability:)
        name = capability_name(capability)
        return unless name

        row = model.fetch("performance", {})[name]
        return unless row

        attempts = row.fetch("attempts", 0).to_i
        samples = row.fetch("confidence_observations", 0).to_i
        {
          capability: name,
          attempts:,
          successes: row.fetch("successes", 0).to_i,
          failures: row.fetch("failures", 0).to_i,
          accuracy: attempts.positive? ? row.fetch("successes", 0).to_f / attempts : nil,
          confidence_observations: samples,
          mean_confidence: samples.positive? ? row.fetch("confidence_sum", 0.0).to_f / samples : nil,
          brier_score: samples.positive? ? row.fetch("brier_sum", 0.0).to_f / samples : nil,
        }.freeze
      end

      # Recommend the review depth from observed outcomes, never from a generated
      # confidence statement alone. Small samples and absent records are explicitly
      # inconclusive, so they cannot steer execution strategy.
      def decision_posture(model, capability:, minimum_attempts: MIN_POSTURE_ATTEMPTS,
                           minimum_calibration_samples: MIN_POSTURE_CALIBRATION_SAMPLES)
        stats = performance(model, capability:)
        return { posture: :insufficient_evidence, strategy: nil, attempts: 0, accuracy: nil }.freeze unless stats
        return { posture: :insufficient_evidence, strategy: nil, attempts: stats[:attempts], accuracy: stats[:accuracy] }.freeze if stats[:attempts] < minimum_attempts

        poorly_calibrated = stats[:confidence_observations] >= minimum_calibration_samples &&
                            stats[:brier_score].to_f >= ADVERSARIAL_BRIER_THRESHOLD
        mildly_miscalibrated = stats[:confidence_observations] >= minimum_calibration_samples &&
                               stats[:brier_score].to_f >= ENSEMBLE_BRIER_THRESHOLD
        strategy = if stats[:accuracy].to_f < ADVERSARIAL_ACCURACY_THRESHOLD || poorly_calibrated
          :adversarial
        elsif stats[:accuracy].to_f < ENSEMBLE_ACCURACY_THRESHOLD || mildly_miscalibrated
          :ensemble
        else
          :consensus
        end
        { posture: :measured, strategy:, attempts: stats[:attempts], accuracy: stats[:accuracy],
          confidence_observations: stats[:confidence_observations], brier_score: stats[:brier_score] }.freeze
      end

      def reflection(model, metrics:, affect:)
        stance = model.fetch("capabilities", CAPABILITIES).fetch("phenomenal_consciousness", "unknown")
        base = "I am #{stance} about phenomenal consciousness; my workspace-activity proxy is " \
               "#{metrics.fetch("workspace_activity", 0.0).round(3)}, prediction error " \
               "#{metrics.fetch("prediction_error", 0.0).round(3)}, valence " \
               "#{affect.fetch("valence", 0.0).round(3)}."
        measured = model.fetch("performance", {}).filter_map do |name, row|
          next unless row.is_a?(Hash) && row.fetch("attempts", 0).to_i.positive?

          stats = performance(model, capability: name)
          "#{name} #{stats[:successes]}/#{stats[:attempts]} successes"
        end.first(3)
        measured.empty? ? base : "#{base} Observed outcomes (descriptive): #{measured.join("; ")}."
      end

      private

      def record_performance!(model, payload)
        return unless payload.is_a?(Hash)

        success = payload.key?(:ok) ? payload[:ok] : payload["ok"]
        return unless success == true || success == false

        raw_name = payload[:capability] || payload["capability"] ||
                   payload[:task_type] || payload["task_type"] ||
                   payload[:tool_name] || payload["tool_name"] ||
                   payload[:tool] || payload["tool"]
        name = capability_name(raw_name)
        return unless name

        performance = model["performance"] ||= {}
        row = performance[name] ||= {
          "attempts" => 0, "successes" => 0, "failures" => 0,
          "confidence_observations" => 0, "confidence_sum" => 0.0, "brier_sum" => 0.0,
          "last_at" => 0
        }
        row["attempts"] = row.fetch("attempts", 0).to_i + 1
        outcome_key = success ? "successes" : "failures"
        row[outcome_key] = row.fetch(outcome_key, 0).to_i + 1
        row["last_at"] = Time.now.to_i

        raw_confidence = payload[:predicted_confidence] || payload["predicted_confidence"]
        return unless raw_confidence.is_a?(Numeric) && raw_confidence.to_f.finite?

        confidence = raw_confidence.to_f
        return unless confidence.between?(0.0, 1.0)

        observed = success ? 1.0 : 0.0
        row["confidence_observations"] = row.fetch("confidence_observations", 0).to_i + 1
        row["confidence_sum"] = row.fetch("confidence_sum", 0.0).to_f + confidence
        row["brier_sum"] = row.fetch("brier_sum", 0.0).to_f + ((confidence - observed)**2)
      end

      def capability_name(value)
        name = value.to_s.strip.downcase
        name.match?(State::IDENTIFIER_PATTERN) ? name : nil
      end

      def summarize(payload)
        return {} unless payload.is_a?(Hash)

        payload.each_with_object({}) do |(key, value), out|
          out[key.to_s] = value.is_a?(Numeric) || value == true || value == false ? value : value.to_s[0, 200]
        end
      end

      def prune!(model)
        beliefs = model.keys.grep(%r{\Aevent/}).sort_by { |key| -model.dig(key, "last_at").to_i }
        beliefs.drop(MAX_BELIEFS).each { |key| model.delete(key) }

        performance = model["performance"]
        return unless performance.is_a?(Hash) && performance.size > MAX_PERFORMANCE_BUCKETS
          performance.keys.sort_by { |name| -performance.dig(name, "last_at").to_i }
                     .drop(MAX_PERFORMANCE_BUCKETS).each { |name| performance.delete(name) }

      end
    end
  end
end
