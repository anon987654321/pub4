# frozen_string_literal: true
#
# PATCH: additions to lib/llm.rb
# Insert these into the LLM module class << self block,
# alongside the existing replicate_api_key / configured_for_replicate? methods.
#
# ALSO: update FREE_FALLBACKS to add meta/llama-4-scout as a Replicate free fallback.
#
# FREE_FALLBACKS replacement:
#
#   FREE_FALLBACKS = %w[
#     meta-llama/llama-3.3-70b-instruct:free
#     google/gemma-3-12b-it:free
#     meta/llama-4-scout
#   ].freeze
#

module MASTER
  module LLM
    FREE_FALLBACKS = %w[
      meta-llama/llama-3.3-70b-instruct:free
      google/gemma-3-12b-it:free
      meta/llama-4-scout
    ].freeze

    class << self
      # Returns true when the model's api field in models.yml is "replicate".
      # Uses the existing configured_models_by_id hash for O(1) lookup.
      def replicate_model?(model_id)
        m = configured_models_by_id[model_id]
        m && m[:api].to_s == "replicate"
      end

      # Text-generation via Replicate, using Client.complete which:
      #   - builds model-family-aware input (anthropic vs deepseek vs default schema)
      #   - creates prediction via /v1/models/{owner}/{name}/predictions
      #   - polls until done and returns a normalised Result
      # This keeps llm.rb thin: all HTTP/polling logic stays in replicate/client.rb.
      def execute_replicate_llm_request(prompt:, messages:, model:, reasoning: nil)
        require_relative "replicate/client"

        unless Replicate.available?
          return Result.err("REPLICATE_API_TOKEN not set", category: :infrastructure)
        end

        # Extract system prompt from messages array if present
        sys = messages&.find { |m| m[:role] == "system" }
        system_prompt = sys&.dig(:content)

        # reasoning_effort is advisory — pass it through; Anthropic on Replicate
        # honours it when the field is recognised, ignores it otherwise.
        opts = {}
        opts[:reasoning_effort] = reasoning[:effort].to_s if reasoning.is_a?(Hash) && reasoning[:effort]

        Replicate::Client.complete(model, prompt, system_prompt: system_prompt, **opts)
      end
    end
  end
end
