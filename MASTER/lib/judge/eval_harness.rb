# frozen_string_literal: true

require "yaml"

module Master
  module Judge
    # Eval harness: score a subject (a prompt, an agent config) against a fixed set of cases.
    # Gives MASTER the automated regression metric it lacked AND the objective that GEPA /
    # PromptEvolver needs (scorer = ->(prompt) { harness.score(prompt) }). Dependency-injected
    # and pure Ruby: `runner` produces output, `scorer` grades it 0.0..1.0.
    class EvalHarness
      Case = Struct.new(:input, :expect, keyword_init: true)

      # Load cases from a YAML eval set: { cases: [ { input:, expect: }, ... ] } (keys configurable).
      def self.cases_from_yaml(path, input_key: "input", expect_key: "expect", root_key: "cases")
        data = YAML.safe_load(File.read(path)) || {}
        rows = data[root_key] || data.values.find { |value| value.is_a?(Array) } || []
        rows.filter_map do |row|
          Case.new(input: row[input_key], expect: row[expect_key]) if row.is_a?(Hash)
        end
      rescue StandardError
        []
      end

      def initialize(cases:, runner:, scorer:)
        @cases = Array(cases)
        @runner = runner       # callable: (subject, input) -> output
        @scorer = scorer       # callable: (output, expect) -> 0.0..1.0
      end

      # Mean score across all cases — the GEPA objective and the regression metric.
      def score(subject)
        return 0.0 if @cases.empty?

        report(subject).sum { |row| row[:score] }.to_f / @cases.size
      end

      # Per-case scores, for regression diffing between runs.
      def report(subject)
        @cases.map { |kase| { input: kase.input, score: grade(subject, kase) } }
      end

      private

      def grade(subject, kase)
        output = @runner.call(subject, kase.input)
        @scorer.call(output, kase.expect).to_f.clamp(0.0, 1.0)
      rescue StandardError
        0.0
      end
    end
  end
end
