# frozen_string_literal: true

require_relative "../result"

module MASTER
  module Replicate
    # LLM - Text generation via Replicate predictions API
    # Used for: Claude Sonnet 4.6, DeepSeek R1/V3, and other text LLMs on Replicate
    # Auth: REPLICATE_API_TOKEN
    #
    # Input schema varies by model family:
    #   anthropic/* → prompt, system, max_tokens, temperature
    #   deepseek-ai/* → prompt, system_prompt, max_tokens, temperature, top_p, top_k
    #   default       → deepseek-style schema (most open LLMs on Replicate)
    #
    # Output: array of token strings → joined into full response
    module LLM
      extend self

      DEFAULT_MAX_TOKENS  = 4_096
      DEFAULT_TEMPERATURE = 0.6 # recommended for R1; 0.7–1.0 for other models
      DEFAULT_TOP_P       = 0.95

      def complete(model_id, prompt, system_prompt: nil, max_tokens: DEFAULT_MAX_TOKENS,
                   temperature: DEFAULT_TEMPERATURE, top_p: DEFAULT_TOP_P, **_opts)
        input = build_input(model_id, prompt, system_prompt, max_tokens, temperature, top_p)

        prediction = Client.create_prediction(model: model_id, input: input)
        return Result.err("Replicate prediction failed: #{prediction[:error]}") if prediction[:error]

        completion = Client.wait_for_completion(prediction[:id])
        return Result.err("Replicate completion failed: #{completion[:error]}") if completion[:error]

        # Output is an array of token strings on Replicate; join for full text
        content = Array(completion[:output]).join

        return Result.err("Empty response from #{model_id.split('/').last}") if content.strip.empty?

        Result.ok(
          content: content,
          model: model_id,
          provider: :replicate,
          tokens_in: 0, # Replicate predictions API doesn't surface token counts
          tokens_out: 0,
          cost: nil,
          finish_reason: "stop",
        )
      rescue StandardError => e
        Result.err("Replicate LLM error: #{e.message}", category: :infrastructure)
      end

      private

      # Build model-family–aware input hash for Replicate's predictions API
      def build_input(model_id, prompt, system_prompt, max_tokens, temperature, top_p)
        owner = model_id.split("/").first

        h = case owner
            when "anthropic"
              { prompt: prompt, max_tokens: [max_tokens, 1024].max, temperature: temperature }
            when "deepseek-ai"
              { prompt: prompt, max_tokens: max_tokens, temperature: temperature, top_p: top_p }
            else
              # Default: deepseek-style (most open LLMs on Replicate use this schema)
              { prompt: prompt, max_tokens: max_tokens, temperature: temperature, top_p: top_p }
            end
        h[:system_prompt] = system_prompt if system_prompt
        h
      end
    end
  end
end
