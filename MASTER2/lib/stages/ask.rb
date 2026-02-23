# frozen_string_literal: true

module MASTER
  module Stages
    # Stage 6: Query LLM with streaming output
    class Ask
      def call(input)
        if defined?(Logging)
          Logging.dmesg_log("ask0", parent: "pipeline0", message: "ENTER ask",
                                    level: Logging::ALL_EVENTS)
        end
        model = input[:model]
        return Result.err("No model selected.", category: :infrastructure) unless model

        model_short = model.split("/").last
        tier = input[:tier] || :unknown
        puts UI.dim("models0: #{tier} #{model_short}")

        text = input[:text] || ""

        result = LLM.ask(text, model: model, stream: true)

        if result.ok?
          llm_response = result.value
          tokens_in = llm_response.fetch(:tokens_in, 0)
          tokens_out = llm_response.fetch(:tokens_out, 0)
          cost = llm_response.fetch(:cost, 0)

          puts UI.dim("models0: #{tokens_in}->#{tokens_out} tok, #{UI.currency_precise(cost)}")

          Result.ok(input.merge(
                      response: llm_response[:content],
                      tokens_in: tokens_in,
                      tokens_out: tokens_out,
                      cost: cost,
                    ))
        else
          # Propagate category from underlying LLM result if available
          cat = result.respond_to?(:category) ? result.category : :infrastructure
          Result.err("LLM error (#{model}): #{result.error}.", category: cat)
        end
      end
    end
  end
end
