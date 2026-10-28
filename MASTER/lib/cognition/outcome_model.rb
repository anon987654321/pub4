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
      MAX_EVIDENCE_BYTES = 2 * 1024 * 1024
      MAX_OBSERVATIONS = 12
      MAX_SEEN_RECEIPTS = 64
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
          "seen_receipts" => [],
        }

        seen = Array(record["seen_receipts"])
        duplicate = seen.find do |item|
          item["source"] == receipt.fetch("source") && item["sha256"] == receipt.fetch("sha256")
        end
        if duplicate
          raise ArgumentError, "evidence receipt reused with a different outcome" unless duplicate["outcome"] == outcome

          return predict(state, context:, action:)
        end

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
        record["seen_receipts"] = (seen + [{
          "source" => receipt.fetch("source"),
          "sha256" => receipt.fetch("sha256"),
          "outcome" => outcome,
        }]).last(MAX_SEEN_RECEIPTS)
        record["last_source"] = receipt.fetch("source")
        record["last_sha256"] = receipt.fetch("sha256")
        record["updated_at"] = stamp
        prune!(records)
        predict(state, context:, action:)
      end

      # A receipt is either inline content whose digest is checked here, or a
      # file whose current digest is checked against a root-confined path.
      # Event delivery is at-least-once in some adapters. A receipt may train a
      # given task/action pair only once; a changed verdict for the same bytes is
      # a contradiction, not a second independent observation.
      def duplicate?(state, context:, action:, outcome:, evidence:)
        receipt = self.class.validate_evidence!(evidence)
        key = key_for(context:, action:)
        record = state.fetch("records", {})[key]
        return false unless record

        seen = Array(record["seen_receipts"]).find do |item|
          item["source"] == receipt.fetch("source") && item["sha256"] == receipt.fetch("sha256")
        end
        return false unless seen
        raise ArgumentError, "evidence receipt reused with a different outcome" unless seen["outcome"] == outcome.to_s

        true
      end

      def self.validate_evidence!(evidence, root: nil)
        row = evidence.respond_to?(:to_h) ? evidence.to_h : nil
        raise ArgumentError, "evidence receipt must be a hash" unless row

        source = (row[:source] || row["source"]).to_s.strip
        supplied = (row[:sha256] || row["sha256"]).to_s.downcase
        raise ArgumentError, "evidence source is required" if source.empty?
        raise ArgumentError, "evidence source exceeds #{LABEL_LIMIT} characters" if source.length > LABEL_LIMIT

        if row.key?(:content) || row.key?("content")
          content = row.key?(:content) ? row[:content] : row["content"]
          raise ArgumentError, "evidence content must be a string" unless content.is_a?(String)
          raise ArgumentError, "evidence content exceeds #{MAX_EVIDENCE_BYTES} bytes" if content.bytesize > MAX_EVIDENCE_BYTES
          raise ArgumentError, "evidence SHA-256 must contain 64 hexadecimal characters" unless supplied.match?(/\A[0-9a-f]{64}\z/)

          sha256 = Digest::SHA256.hexdigest(content)
          raise ArgumentError, "evidence content SHA-256 mismatch" unless supplied == sha256
        elsif root
          raise ArgumentError, "evidence SHA-256 must contain 64 hexadecimal characters" unless supplied.match?(/\A[0-9a-f]{64}\z/)

          base = File.realpath(File.expand_path(root))
          path = File.expand_path(source, base)
          raise ArgumentError, "evidence path escapes its root" unless path.start_with?("#{base}/")
          raise ArgumentError, "evidence file is unavailable" unless File.file?(path)

          real_path = File.realpath(path)
          raise ArgumentError, "evidence symlink escapes its root" unless real_path.start_with?("#{base}/")
          raise ArgumentError, "evidence file exceeds #{MAX_EVIDENCE_BYTES} bytes" if File.size(real_path) > MAX_EVIDENCE_BYTES

          content = File.binread(real_path)
          sha256 = Digest::SHA256.hexdigest(content)
          raise ArgumentError, "evidence file SHA-256 mismatch" unless supplied == sha256
        else
          raise ArgumentError, "evidence requires inline content or a verification root"
        end

        { "source" => source, "sha256" => sha256, "content" => content }.freeze
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
        return if value.nil?

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
