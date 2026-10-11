# frozen_string_literal: true

require "digest"
require "json"
require "time"

module Master
  module Cognition
    # Learns associations between explicit task contexts/actions and verified
    # outcomes. Event adjacency is useful telemetry, not causal proof.
    class OutcomeModel
      OUTCOMES = %w[success failure inconclusive].freeze
      MAX_RECORDS = 256
      MAX_OBSERVATIONS = 12
      LABEL_LIMIT = 160
      MIN_SAMPLES = 5

      def predict(state, context:, action:)
        key = key_for(context:, action:)
        record = state.fetch("records", {})[key] || {}
        successes = record.fetch("successes", 0).to_i
        failures = record.fetch("failures", 0).to_i
        samples = successes + failures
        probability = (successes + 1).to_f / (samples + 2)
        brier_count = record.fetch("brier_count", 0).to_i
        {
          key:,
          samples:,
          successes:,
          failures:,
          inconclusive: record.fetch("inconclusive", 0).to_i,
          success_probability: probability.round(4),
          confidence: (samples.to_f / (samples + 4)).round(4),
          status: samples >= MIN_SAMPLES ? :learned : :insufficient_data,
          prediction: samples.zero? ? :unknown : probability > 0.5 ? :success : probability < 0.5 ? :failure : :uncertain,
          brier_score: brier_count.zero? ? nil : (record.fetch("brier_sum", 0.0).to_f / brier_count).round(4),
          last_source: record["last_source"],
          updated_at: record["updated_at"],
        }.freeze
      end

      def observe!(state, context:, action:, outcome:, evidence:, predicted_probability: nil)
        outcome = outcome.to_s
        raise ArgumentError, "unknown task outcome: #{outcome}" unless OUTCOMES.include?(outcome)

        receipt = self.class.validate_evidence!(evidence)
        probability = probability_value(predicted_probability)
        key = key_for(context:, action:)
        records = state["records"] ||= {}
        record = records[key] ||= {
          "context" => label(context),
          "action" => label(action),
          "successes" => 0,
          "failures" => 0,
          "inconclusive" => 0,
          "brier_sum" => 0.0,
          "brier_count" => 0,
          "observations" => [],
        }

        case outcome
        when "success" then record["successes"] = record.fetch("successes", 0).to_i + 1
        when "failure" then record["failures"] = record.fetch("failures", 0).to_i + 1
        when "inconclusive" then record["inconclusive"] = record.fetch("inconclusive", 0).to_i + 1
        end

        if probability && outcome != "inconclusive"
          target = outcome == "success" ? 1.0 : 0.0
          record["brier_sum"] = record.fetch("brier_sum", 0.0).to_f + ((probability - target)**2)
          record["brier_count"] = record.fetch("brier_count", 0).to_i + 1
        end

        stamp = Time.now.utc.iso8601
        record["observations"] = (
          Array(record["observations"]) + [{
            "outcome" => outcome,
            "source" => receipt.fetch("source"),
            "sha256" => receipt.fetch("sha256"),
            "predicted_probability" => probability,
            "observed_at" => stamp,
          }]
        ).last(MAX_OBSERVATIONS)
        record["last_source"] = receipt.fetch("source")
        record["last_sha256"] = receipt.fetch("sha256")
        record["updated_at"] = stamp
        prune!(records)
        predict(state, context:, action:)
      end

      def self.validate_evidence!(evidence)
        row = evidence.respond_to?(:to_h) ? evidence.to_h : nil
        raise ArgumentError, "evidence receipt must be a hash" unless row

        source = (row[:source] || row["source"]).to_s.strip
        sha256 = (row[:sha256] || row["sha256"]).to_s.downcase
        raise ArgumentError, "evidence source is required" if source.empty?
        raise ArgumentError, "evidence SHA-256 must contain 64 hexadecimal characters" unless sha256.match?(/\A[0-9a-f]{64}\z/)

        { "source" => source[0, LABEL_LIMIT], "sha256" => sha256 }.freeze
      end

      private

      def key_for(context:, action:)
        Digest::SHA256.hexdigest(JSON.generate([canonical(context), canonical(action)]))[0, 24]
      end

      def canonical(value)
        label(value).downcase.gsub(/\s+/, " ")
      end

      def label(value)
        text = value.to_s.strip.gsub(/[\u0000-\u001f]/, " ")
        raise ArgumentError, "context and action must be present" if text.empty?

        text[0, LABEL_LIMIT]
      end

      def probability_value(value)
        return nil if value.nil?

        number = Float(value)
        raise ArgumentError, "predicted probability must be between 0 and 1" unless number.between?(0.0, 1.0)

        number
      rescue TypeError, ArgumentError => e
        raise e if e.message.include?("between 0 and 1")

        raise ArgumentError, "predicted probability must be numeric"
      end

      def prune!(records)
        excess = records.size - MAX_RECORDS
        return unless excess.positive?

        records.keys.first(excess).each { |key| records.delete(key) }
      end
    end
  end
end
