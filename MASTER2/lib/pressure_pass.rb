# frozen_string_literal: true

require "json"

module MASTER
  # Extracted adversarial review pass. Runs structured pressure testing
  # against a candidate answer to harden truthfulness and utility.
  # Reusable by Pipeline, SelfRefactor, or any module that needs
  # adversarial scrutiny of LLM output.
  module PressurePass
    module_function

    CRIT_SESSION_PANEL = [
      {
        role: "adversarial architect",
        ask: "Where does the structure collapse under scale, constraints, or maintenance debt?",
      },
      {
        role: "adversarial web designer",
        ask: "Where does interaction clarity fail for real users, especially under stress?",
      },
      {
        role: "adversarial electronic musician",
        ask: "Where does rhythm, variation, and emotional pacing become repetitive or dead?",
      },
      {
        role: "adversarial indie filmmaker",
        ask: "Where does the narrative lose coherence, tension, or visual intent?",
      },
      {
        role: "adversarial slam poet",
        ask: "Where does language lose impact, authenticity, or memorable cadence?",
      },
    ].freeze

    def enabled?
      val = ENV.fetch("MASTER_PRESSURE_PASS", "false").to_s.strip.downcase
      !%w[0 false off no].include?(val)
    end

    def schema
      {
        type: "object",
        additionalProperties: false,
        required: %w[counterargument failure_modes alternatives selected_index selected_answer rationale],
        properties: {
          counterargument: { type: "string" },
          failure_modes: { type: "array", minItems: 2, items: { type: "string" } },
          alternatives: { type: "array", minItems: 2, items: { type: "string" } },
          selected_index: { type: "integer", minimum: 0 },
          selected_answer: { type: "string" },
          rationale: { type: "string" },
        },
      }
    end

    def prompt(user_input, candidate_text)
      panel = CRIT_SESSION_PANEL.map { |p| "- #{p[:role]}: #{p[:ask]}" }.join("\n")

      <<~PROMPT
        You are an adversarial reviewer. Treat this as hostile scrutiny.
        The goal is stronger truthfulness and utility, not aggression for its own sake.

        User request:
        #{user_input.to_s[0, 4000]}

        Candidate answer:
        #{candidate_text.to_s[0, 6000]}

        Crit session framework (run all lenses):
        #{panel}

        Perform serial pressure testing:
        1) Strongest counterargument against the candidate answer.
        2) Concrete failure modes or risks.
        3) Produce at least 2 improved alternative answers.
        4) Cherry-pick the strongest parts across alternatives into one final answer.
        5) Explain why the cherry-picked final answer wins.

        Constraints:
        - Ask adversarial questions before proposing alternatives.
        - Keep alternatives concise and actionable.
        - No markdown fences.
        - selected_answer must be the final answer to return to the user.
      PROMPT
    end

    # Run the full adversarial review. Returns a structured Hash or nil.
    def review(user_input:, candidate:, tier: :strong)
      return nil unless enabled?
      return nil unless defined?(LLM) && LLM.respond_to?(:configured?) && LLM.configured?
      return nil unless candidate.is_a?(String) && !candidate.strip.empty?
      return nil unless user_input.is_a?(String) && !user_input.strip.empty?

      result = LLM.ask_json(prompt(user_input, candidate), schema: schema, tier: tier, stream: false)
      return nil unless result&.ok?

      parsed = normalize_payload(result.value[:content])
      return nil unless parsed.is_a?(Hash)

      selected = parsed[:selected_answer].to_s.strip
      return nil if selected.empty?

      {
        counterargument: parsed[:counterargument].to_s,
        failure_modes: Array(parsed[:failure_modes]).map(&:to_s),
        alternatives: Array(parsed[:alternatives]).map(&:to_s),
        selected_index: parsed[:selected_index].to_i,
        selected_answer: selected,
        rationale: parsed[:rationale].to_s,
      }
    rescue StandardError
      nil
    end

    def normalize_payload(payload)
      case payload
      when Hash then payload.transform_keys { |k| k.to_s.to_sym }
      when String
        parsed = JSON.parse(payload)
        parsed.is_a?(Hash) ? parsed.transform_keys { |k| k.to_s.to_sym } : nil
      end
    rescue JSON::ParserError
      nil
    end
  end
end
