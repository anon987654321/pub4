# frozen_string_literal: true

require_relative "../mode"
require_relative "rule"

module MASTER
  module Policy
    # Evaluates all applicable PolicyRules against a mode + input/output pair.
    # Returns Result.ok(violations:, ok:) — never raises.
    class Enforcer
      def initialize(rules: default_rules)
        @rules = rules
      end

      def evaluate(mode:, input:, output:)
        policy_violations = []

        @rules.each do |rule|
          next unless rule.applies_to?(mode)
          next unless (v = rule.evaluate(input: input, output: output))

          policy_violations << v.merge(id: rule.id, severity: rule.severity)
        end

        hard_fail = policy_violations.any? { |v| v[:severity] == :hard }
        Result.ok(policy_violations: policy_violations, ok: !hard_fail)
      rescue StandardError => e
        Result.ok(
          policy_violations: [{ id: "ENFORCER_ERROR", severity: :soft, message: e.message }],
          ok: true,
        )
      end

      private

      def default_rules
        [
          Rule.new(
            id:          "OPS_NO_NARRATIVE",
            severity:    :hard,
            modes:       [Mode::OPS],
            description: "No narrative/story continuation in ops mode.",
          ) do |_input, output|
            next nil unless output.is_a?(String)
            if output.match?(/^\s*Chapter\s+\d+/i) || output.match?(/\bTo be continued\b/i)
              { message: "Narrative markers detected in ops output." }
            end
          end,

          Rule.new(
            id:          "OPS_NO_UNGROUNDED_EXECUTION_CLAIMS",
            severity:    :hard,
            modes:       [Mode::OPS],
            description: "Do not claim to have executed commands unless tool evidence exists.",
          ) do |_input, output|
            next nil unless output.is_a?(String)
            if output.match?(/\bI (?:ran|executed|deployed|installed)\b/i) &&
               !output.match?(/\b(?:exit(?:_code)?|stderr|stdout|tool_id|hash=)\b/i)
              { message: "Execution claim without evidence markers." }
            end
          end,

          # Soft rule: unverified plans/predictions in ops mode must be labelled
          # "Hypothesis:" so the operator knows the model didn't observe this.
          # Allows the output through but attaches a violation for metrics.
          Rule.new(
            id:          "OPS_HYPOTHESIS_LABELLING",
            severity:    :soft,
            modes:       [Mode::OPS],
            description: "Unverified predictions in ops mode should be prefixed 'Hypothesis:'.",
          ) do |_input, output|
            next nil unless output.is_a?(String)
            # Trigger on forward-looking certainty language without evidence anchors
            if output.match?(/\bthis (?:will|should|would|must) (?:fix|work|succeed|pass|deploy|install)\b/i) &&
               !output.match?(/\b(?:hash=|exit=|Hypothesis:|hypothesis:)\b/)
              { message: "Unverified prediction detected. Prefix with 'Hypothesis:' or attach evidence." }
            end
          end,
        ]
      end
    end
  end
end
