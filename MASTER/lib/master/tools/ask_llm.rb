# frozen_string_literal: true

module Master
  module Tools
    # AskLlm — delegate sub-questions to the LLM agent mid-pipeline.
    class AskLlm
      TIER        = :guarded
      NAME        = "ask_llm".freeze
      DESCRIPTION = "Ask the LLM a sub-question and return the answer as a string.".freeze

      def initialize(agent:, governor:, circuit_breaker:, cache:, event_bus: nil)
        @agent          = agent
        @governor       = governor
        @circuit_breaker = circuit_breaker
        @cache          = cache
        @bus            = event_bus
      end

      def call(prompt:, context: nil)
        perm = @governor.permit?(NAME, TIER, prompt[0, 60])
        return perm if perm.err?

        @bus&.publish("tool:before", tool: NAME, prompt: prompt[0, 80])

        result = @circuit_breaker.call(estimate_cost(prompt)) {
          @cache.fetch(prompt, @agent.model) {
            @agent.ask(prompt, context: context)
          }
        }

        @bus&.publish("tool:after", tool: NAME)
        Result.ok(result.to_s)
      rescue StandardError => e
        Result.err("ask_llm: #{e.message}", category: :unknown)
      end

      private

      def estimate_cost(prompt)
        (prompt.bytesize / 4) * 0.000_015
      end
    end
  end
end
