# frozen_string_literal: true

module Master
  module Cognition
    # Explicit, revisable beliefs about MASTER itself. Capability quality is
    # estimated from evidence-backed task outcomes, not fluent self-description.
    #
    # phenomenal_consciousness stays unknown: adding code cannot settle that claim.
    class SelfModel
      MAX_BELIEFS = 32
      MAX_ASSESSMENT_TYPES = 64
      MAX_ASSESSMENT_RECEIPTS = 16

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
        prune!(model)
        model
      end

      # Record an observed binary outcome and, when provided, a probability that
      # was expressed before the result. Brier score then measures calibration.
      def record_assessment!(model, task_type:, success:, confidence: nil, source:, evidence_sha256:)
        raise ArgumentError, "success must be true or false" unless [true, false].include?(success)

        task = task_type.to_s.strip.downcase.gsub(/[^a-z0-9_.:-]+/, "_")[0, 80]
        raise ArgumentError, "task type is required" if task.empty?
        receipt_source = source.to_s.strip
        digest = evidence_sha256.to_s.downcase
        raise ArgumentError, "evidence source is required" if receipt_source.empty?
        raise ArgumentError, "evidence SHA-256 must contain 64 hexadecimal characters" unless digest.match?(/\A[0-9a-f]{64}\z/)

        probability = confidence.nil? ? nil : Float(confidence)
        raise ArgumentError, "confidence must be between 0 and 1" if probability && !probability.between?(0.0, 1.0)

        assessments = model["assessments"] ||= {}
        row = assessments[task] ||= {
          "samples" => 0, "successes" => 0, "failures" => 0,
          "confidence_sum" => 0.0, "brier_sum" => 0.0, "calibration_samples" => 0,
          "receipts" => [],
        }
        row["samples"] = row.fetch("samples", 0).to_i + 1
        field = success ? "successes" : "failures"
        row[field] = row.fetch(field, 0).to_i + 1
        brier = nil
        if probability
          target = success ? 1.0 : 0.0
          brier = (probability - target)**2
          row["confidence_sum"] = row.fetch("confidence_sum", 0.0).to_f + probability
          row["brier_sum"] = row.fetch("brier_sum", 0.0).to_f + brier
          row["calibration_samples"] = row.fetch("calibration_samples", 0).to_i + 1
        end
        row["last_at"] = Time.now.to_i
        row["receipts"] = (Array(row["receipts"]) + [{
          "success" => success, "confidence" => probability, "brier" => brier,
          "source" => receipt_source[0, 160], "sha256" => digest, "at" => row["last_at"],
        }]).last(MAX_ASSESSMENT_RECEIPTS)
        prune_assessments!(assessments)
        assessment_summary(model).fetch(task)
      end

      def assessment_summary(model)
        (model["assessments"] || {}).to_h do |task, row|
          samples = row.fetch("samples", 0).to_i
          calibration_samples = row.fetch("calibration_samples", 0).to_i
          confidence = calibration_samples.zero? ? nil : row.fetch("confidence_sum", 0.0).to_f / calibration_samples
          brier = calibration_samples.zero? ? nil : row.fetch("brier_sum", 0.0).to_f / calibration_samples
          [task, {
            samples:,
            successes: row.fetch("successes", 0).to_i,
            failures: row.fetch("failures", 0).to_i,
            success_rate: samples.zero? ? nil : (row.fetch("successes", 0).to_f / samples).round(4),
            calibration_samples:,
            mean_confidence: confidence&.round(4),
            brier_score: brier&.round(4),
            last_at: row["last_at"],
            evidence_sources: Array(row["receipts"]).map { |receipt| receipt["source"] }.uniq,
          }.freeze]
        end.freeze
      end

      def reflection(model, metrics:, affect:)
        stance = model.fetch("capabilities", CAPABILITIES).fetch("phenomenal_consciousness", "unknown")
        text = [
          "I am #{stance} about phenomenal consciousness; my integrated-state proxy is #{metrics.fetch("integration", 0.0).round(3)},",
          "prediction error #{metrics.fetch("prediction_error", 0.0).round(3)}, valence #{affect.fetch("valence", 0.0).round(3)}.",
        ].join(" ")
        measured = assessment_summary(model).sort_by { |_task, row| -row[:samples] }.first(3)
        return text if measured.empty?

        details = measured.map do |task, row|
          calibration = row[:brier_score] ? ", Brier=#{row[:brier_score]}" : ", calibration unavailable"
          "#{task}: n=#{row[:samples]}, observed success rate=#{row[:success_rate]}#{calibration}"
        end.join("; ")
        "#{text} Recorded task outcomes (not independent confirmation): #{details}."
      end

      private

      def summarize(payload)
        return {} unless payload.is_a?(Hash)

        payload.each_with_object({}) do |(key, value), out|
          out[key.to_s] = value.is_a?(Numeric) || value == true || value == false ? value : value.to_s[0, 200]
        end
      end

      def prune!(model)
        beliefs = model.keys.grep(%r{\Aevent/}).sort_by { |key| -model.dig(key, "last_at").to_i }
        beliefs.drop(MAX_BELIEFS).each { |key| model.delete(key) }
      end

      def prune_assessments!(assessments)
        excess = assessments.size - MAX_ASSESSMENT_TYPES
        return unless excess.positive?

        assessments.sort_by { |_task, row| row.fetch("last_at", 0).to_i }.first(excess).each do |task, _|
          assessments.delete(task)
        end
      end
    end
  end
end
