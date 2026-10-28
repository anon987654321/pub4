# frozen_string_literal: true

require_relative "outcome_model"

module Master
  module Cognition
    # Prequential benchmark: each prediction is scored before its observation is
    # added to memory. The constant 0.5 baseline shows whether learning helps.
    # Input rows must come from real, independently evidenced task outcomes.
    module Benchmark
      module_function

      def evaluate(rows, learn: true, root: nil)
        inputs = Array(rows)
        model = OutcomeModel.new
        state = { "records" => {} }
        scored = []

        inputs.each_with_index do |input, index|
          row = input.respond_to?(:to_h) ? input.to_h : nil
          raise ArgumentError, "row #{index + 1} must be a hash" unless row

          context = fetch(row, :context)
          action = fetch(row, :action)
          outcome = fetch(row, :outcome).to_s
          evidence = fetch(row, :evidence)
          raise ArgumentError, "row #{index + 1} has an invalid outcome" unless OutcomeModel::OUTCOMES.include?(outcome)
          receipt = OutcomeModel.validate_evidence!(evidence, root:)

          prediction = model.predict(state, context:, action:)
          if %w[success failure].include?(outcome)
            actual = outcome == "success" ? 1.0 : 0.0
            scored << {
              "index" => index + 1,
              "actual" => outcome,
              "probability" => prediction.fetch(:success_probability),
              "brier" => (prediction.fetch(:success_probability) - actual)**2,
              "baseline_brier" => 0.25,
              "prior_samples" => prediction.fetch(:samples),
              "source" => receipt.fetch("source"),
            }
          end
          if learn
            model.observe!(state, context:, action:, outcome:, evidence: receipt,
                           predicted_probability: prediction.fetch(:success_probability))
          end
        end

        learned_brier = mean(scored.map { |row| row["brier"] })
        baseline_brier = mean(scored.map { |row| row["baseline_brier"] })
        classified = scored.reject { |row| row["probability"] == 0.5 }
        correct = classified.count do |row|
          (row["probability"] > 0.5) == (row["actual"] == "success")
        end

        {
          "mode" => learn ? "learning" : "ablation_no_learning",
          "observations" => inputs.size,
          "scored_outcomes" => scored.size,
          "learned_brier_score" => learned_brier,
          "constant_baseline_brier_score" => baseline_brier,
          "brier_improvement" => learned_brier && baseline_brier ? (baseline_brier - learned_brier).round(4) : nil,
          "classified_outcomes" => classified.size,
          "classification_accuracy" => classified.empty? ? nil : (correct.to_f / classified.size).round(4),
          "prediction_coverage" => scored.empty? ? 0.0 : (classified.size.to_f / scored.size).round(4),
          "interpretation" => "descriptive only; requires enough independent, representative outcomes",
          "rows" => scored,
        }
      end

      def fetch(row, key)
        value = row[key] || row[key.to_s]
        raise ArgumentError, "missing #{key}" if value.nil?

        value
      end
      private_class_method :fetch

      def mean(values)
        return if values.empty?

        (values.sum.to_f / values.size).round(4)
      end
      private_class_method :mean
    end
  end
end
