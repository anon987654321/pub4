# frozen_string_literal: true

module MASTER
  module Stages
    # Ask: Call LLM to generate a response
    class Ask
      def call(input)
        text = input[:text] || ""
        
        # Select model based on text length
        model = LLM.select_model(text.length)
        return Result.err("No LLM model available (budget exhausted or all circuits tripped)") unless model

        begin
          # Create chat instance
          chat = LLM.chat(model: model)
          
          # Apply persona instructions if available
          persona = input[:persona_instructions]
          chat.with_instructions(persona) if persona && chat.respond_to?(:with_instructions)

          # Call LLM with streaming to stderr
          response = chat.ask(text) do |chunk|
            $stderr.print chunk.content if chunk.content
          end
          $stderr.puts

          # Extract tokens from response (RubyLLM uses input_tokens/output_tokens)
          tokens_in = response.input_tokens rescue 0
          tokens_out = response.output_tokens rescue 0
          
          # Record cost
          LLM.record_cost(model: model, tokens_in: tokens_in, tokens_out: tokens_out)
          
          # Record success
          LLM.record_success(model)

          # Check circuit state after call
          circuit_state = LLM.circuit_available?(model) ? :available : :tripped

          # Merge response into pipeline hash
          Result.ok(input.merge(
            response: response.content,
            tokens_in: tokens_in,
            tokens_out: tokens_out,
            model_used: model,
            circuit_state: circuit_state
          ))
        rescue => e
          # Record failure
          LLM.record_failure(model)
          Result.err("LLM error (#{model}): #{e.message}")
        end
      end
    end
  end
end
