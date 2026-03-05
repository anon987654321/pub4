# frozen_string_literal: true

require "json"

module MASTER
  # Extracted adversarial review pass. Runs structured pressure testing
  # against a candidate answer to harden truthfulness and utility.
  # Reusable by Pipeline, SelfRefactor, or any module that needs
  # adversarial scrutiny of LLM output.
  module Refinement
    module_function

    # Max chars of user input included in adversarial prompt
    USER_INPUT_LIMIT = 4000
    # Max chars of candidate answer included in adversarial prompt
    CANDIDATE_TEXT_LIMIT = 6000

    def enabled?
      env_val = ENV.fetch("MASTER_PRESSURE_PASS", "false").to_s.strip.downcase
      !%w[0 false off no].include?(env_val)
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
      <<~PROMPT
        You are an adversarial reviewer. Treat this as hostile scrutiny.
        The goal is stronger truthfulness and utility, not aggression for its own sake.

        User request:
        #{user_input.to_s[0, USER_INPUT_LIMIT]}

        Candidate answer:
        #{candidate_text.to_s[0, CANDIDATE_TEXT_LIMIT]}

        Perform serial pressure testing:
        1) Strongest counterargument against the candidate answer.
        2) Concrete failure modes or risks.
        3) Produce at least 2 improved alternative answers.
        4) Choose the best one and explain why.

        Constraints:
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

      llm_result = LLM.ask_json(prompt(user_input, candidate), schema: schema, tier: tier, stream: false)
      return nil unless llm_result&.ok?

      review_data = normalize_payload(llm_result.value[:content])
      return nil unless review_data.is_a?(Hash)

      selected = review_data[:selected_answer].to_s.strip
      return nil if selected.empty?

      {
        counterargument: review_data[:counterargument].to_s,
        failure_modes: Array(review_data[:failure_modes]).map(&:to_s),
        alternatives: Array(review_data[:alternatives]).map(&:to_s),
        selected_index: review_data[:selected_index].to_i,
        selected_answer: selected,
        rationale: review_data[:rationale].to_s,
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
