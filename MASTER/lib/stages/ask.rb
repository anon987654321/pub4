# frozen_string_literal: true

module MASTER
  module Stages
    class Ask
      def initialize
        @circuit = Circuit.new(DB)
        @budget = Budget.new(DB)
      end

      def call(input)
        model = input[:model] || input["model"] || LLM.default_model
        text = input[:text] || input["text"]
        persona = input[:persona] || input["persona"]
        
        begin
          # Create chat instance
          chat = RubyLLM.chat(model: model)
          
          # Add persona instructions if present
          chat.system(persona) if persona
          
          # Ask with streaming
          response = ""
          tokens_in = 0
          tokens_out = 0
          
          result = chat.ask(text) do |chunk|
            response << chunk
            $stderr.print chunk
          end
          
          $stderr.puts # Newline after streaming
          
          # Extract token usage if available
          if result.respond_to?(:usage)
            tokens_in = result.usage[:input_tokens] || 0
            tokens_out = result.usage[:output_tokens] || 0
          end
          
          # Record cost
          cost = @budget.record(model: model, tokens_in: tokens_in, tokens_out: tokens_out)
          
          # Record success
          @circuit.record_success(model)
          
          Result.ok(input.merge(
            response: response,
            tokens_in: tokens_in,
            tokens_out: tokens_out,
            model_used: model,
            cost: cost
          ))
        rescue => e
          # Record failure
          @circuit.record_failure(model)
          Result.err("LLM error: #{e.message}")
        end
      end
    end
  end
end
