# frozen_string_literal: true

module Master
  module Io
    # AskLlm — delegate sub-questions to the LLM agent mid-pipeline.
    class AskLlm
      TIER = :guarded
      NAME = "ask_llm".freeze
      DESCRIPTION = "Ask the LLM a sub-question and return the answer as a string.".freeze

      def initialize(agent:, governor:, circuit_breaker:, cache:, event_bus: nil)
        @agent = agent
        @governor = governor
        @circuit_breaker = circuit_breaker
        @cache = cache
        @bus = event_bus
      end

      def call(prompt:, context: nil)
        perm = @governor.permit?(NAME, TIER, prompt[0, 60])
        return perm if perm.err?

        @bus&.publish("tool:before", tool: NAME, prompt: prompt[0, 80])

        result = @circuit_breaker.call(estimate_cost(prompt)) do
          cache_prompt = "#{prompt}\n--context--\n#{Array(context).to_json}"
          @cache.fetch(cache_prompt, @agent.model) do
            @agent.ask(prompt, context:)
          end
        end

        @bus&.publish("tool:after", tool: NAME)
        Result.ok(result.to_s)
      rescue StandardError => e
        Result.err("ask_llm: #{e.message}", category: :unknown)
      end

      private

      def estimate_cost(prompt)
        Master::Trace::Session.estimate_tokens(prompt) * Review::Agent::COST_PER_TOKEN
      end
    end
  end
end
