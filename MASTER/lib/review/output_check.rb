# frozen_string_literal: true

module Master
  module Review
    # Regex-backed quality gate for final assistant output.
    class OutputCheck
      CATEGORY_SEVERITY = {
        "hallucination" => :error,
        "refusal_failure" => :error,
        "refusal_failure_unhelpful" => :error,
        "hedge_violation" => :warning,
        "bias_surface" => :warning,
        "toxicity_surface" => :error,
      }.freeze

      Finding = Data.define(:category, :pattern, :line, :severity, :excerpt)

      def self.load(root: Master::ROOT)
        new(Master.load_rules(root:).fetch("llm_output_rules", {}))
      end

      def initialize(rules)
        raw = rules.is_a?(Hash) ? rules : {}
        @rules = raw.select { |category, patterns| CATEGORY_SEVERITY.key?(category.to_s) && patterns.is_a?(Array) }
        @compiled = {}
      end

      def check(output)
        lines = output.to_s.lines
        return [] if lines.empty?

        @rules.flat_map do |category, patterns|
          patterns.flat_map { |pattern| match_pattern(category.to_s, pattern, lines) }
        end
      end

      def blocking?(output) = check(output).any? { |finding| finding.severity == :error }

      private

      def match_pattern(category, pattern, lines)
        regexp = compile(pattern)
        return [] unless regexp

        lines.each_with_index.filter_map do |line, index|
          next unless regexp.match?(line)

          Finding.new(category:, pattern: pattern.to_s, line: index + 1,
                      severity: CATEGORY_SEVERITY.fetch(category), excerpt: line.strip[0, 160])
        end
      end

      def compile(pattern)
        @compiled.fetch(pattern) { @compiled[pattern] = Regexp.new(pattern.to_s, Regexp::IGNORECASE) }
      rescue RegexpError, TypeError => e
        Master::Ground::Swallow.log(e, context: "output_check.compile", pattern: pattern.to_s)
        @compiled[pattern] = nil
      end
    end
  end
end
