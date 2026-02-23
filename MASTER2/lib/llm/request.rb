# frozen_string_literal: true

module MASTER
  module LLM
    class << self
      private

      # Retry logic with exponential backoff (3 attempts, 1s/2s/4s delays)
      EXECUTE_MAX_RETRIES = 3
      BACKOFF_BASE = 2

      def execute_with_retry(prompt:, messages:, model:, reasoning:, json_schema:, provider:, stream:)
        retry_count = 0
        last_error = nil

        while retry_count < EXECUTE_MAX_RETRIES
          begin
            result = if replicate_model?(model)
                       execute_replicate_llm_request(prompt: prompt, messages: messages, model: model,
                                                     reasoning: reasoning)
                     else
                       execute_ruby_llm_request(
                         prompt: prompt,
                         messages: messages,
                         model: model,
                         reasoning: reasoning,
                         json_schema: json_schema,
                         provider: provider,
                         stream: stream,
                       )
                     end

            # Success or non-retryable error
            return result if result.ok? || !retryable_error?(result.error)

            last_error = result.error
          rescue ArgumentError => err
            return Result.err("ArgumentError: #{err.message}")
          rescue StandardError => err
            last_error = err.message
          end

          retry_count += 1
          break if retry_count >= EXECUTE_MAX_RETRIES

          # Exponential backoff: 1s, 2s, 4s
          sleep_time = BACKOFF_BASE**(retry_count - 1)
          Logging.warn("LLM retry #{retry_count}/#{EXECUTE_MAX_RETRIES}", delay: sleep_time, error: last_error)
          sleep(sleep_time)
        end

        Result.err("Failed after #{EXECUTE_MAX_RETRIES} retries: #{last_error}")
      end

      def retryable_error?(error)
        return false unless error.is_a?(String) || error.is_a?(Hash)

        error_str = error.is_a?(Hash) ? error[:message].to_s : error.to_s

        # Not retryable: prompt too large
        if error_str.match?(/Prompt tokens limit exceeded: (\d+) > (\d+)/i)
          Logging.warn("Prompt too large — clear history with /clear", subsystem: "llm.context")
          return false
        end

        # Not retryable: insufficient credits — tell user immediately
        if error_str.match?(/requires more credits|can only afford|insufficient credits/i)
          Logging.warn(
            "Insufficient OpenRouter credits — add credits at openrouter.ai/settings/credits or use a free model: `model deepseek-r1-free`", subsystem: "llm.budget"
          )
          return false
        end

        error_str.match?(/timeout|connection|network|429|502|503|504|overloaded/i)
      end

      # Execute request using ruby_llm
      def execute_ruby_llm_request(prompt:, messages:, model:, reasoning:, json_schema:, provider:, stream:)
        configure_ruby_llm

        chat = RubyLLM.chat(model: model, assume_model_exists: true, provider: :openrouter)
          .with_params(max_tokens: LLM::MAX_CHAT_TOKENS)

        # Validate reasoning effort values
        if reasoning
          effort = reasoning.is_a?(Hash) ? reasoning[:effort] : reasoning
          effort_str = effort.to_s
          unless REASONING_EFFORT.map(&:to_s).include?(effort_str)
            return Result.err("Invalid reasoning effort: #{effort_str}. Must be one of: #{REASONING_EFFORT.join(', ')}")
          end

          chat = chat.with_thinking(effort: effort_str.to_sym)
        end

        # JSON schema support
        if json_schema
          schema_data = json_schema[:schema] || json_schema
          chat = chat.with_schema(schema_data)
        end

        # Provider preferences
        chat = chat.with_params(provider: provider) if provider.is_a?(Hash)

        # Build proper message array for RubyLLM (preserves multi-turn conversations)
        msg_array = build_message_array(prompt, messages)

        # Extract system message if present (proper role separation)
        system_msg = msg_array.find { |msg| msg[:role] == "system" }
        if system_msg
          chat = chat.with_instructions(system_msg[:content])
          msg_array = msg_array.reject { |msg| msg[:role] == "system" }
        end

        # Execute query with proper message array
        if stream
          execute_streaming_ruby_llm(chat, msg_array, model)
        else
          execute_blocking_ruby_llm(chat, msg_array, model)
        end
      rescue StandardError => err
        Result.err(Logging.format_error(err))
      end

      # Build message array preserving full conversation history with proper role separation
      def build_message_array(prompt, messages)
        result = []

        if messages.is_a?(Array) && !messages.empty?
          # Convert existing messages to proper format
          messages.each do |msg|
            role = (msg[:role] || msg["role"]).to_s
            content = msg[:content] || msg["content"]
            next unless content

            result << { role: role, content: content }
          end
        end

        # Add current prompt as user message if provided
        result << { role: "user", content: prompt.to_s } if prompt && !prompt.to_s.empty?

        result
      end

      # Replay conversation history into chat object and return final message
      def replay_chat_history(chat, msg_array)
        return "" if msg_array.nil? || msg_array.empty?

        # For multi-turn conversations, add all but the last message to history
        if msg_array.size > 1
          msg_array[0..-2].each do |msg|
            role = msg[:role] || msg["role"]
            content = msg[:content] || msg["content"]
            next unless role && content

            chat.add_message(role: role.to_sym, content: content)
          end
        end

        # Return the final user message content as a string
        final_msg = msg_array.last
        if final_msg.is_a?(Hash)
          final_msg[:content] || final_msg["content"] || ""
        else
          final_msg.to_s
        end
      end

      def execute_blocking_ruby_llm(chat, msg_array, model)
        # Replay history and extract final message string
        message = replay_chat_history(chat, msg_array)
        response = chat.ask(message)

        response_data = {
          content: response.content,
          reasoning: (response.thinking if response.respond_to?(:thinking)),
          model: model,
          tokens_in: response.input_tokens || 0,
          tokens_out: response.output_tokens || 0,
          cost: nil,
          finish_reason: "stop",
        }

        validate_response(response_data, model)
      rescue StandardError => err
        Result.err("ruby_llm error: #{err.message}")
      end

      # Streaming with size limits and proper token counts
      def execute_streaming_ruby_llm(chat, msg_array, model)
        content_parts = []
        reasoning_parts = []
        total_size = 0
        final_response = nil

        # Replay history and extract final message string
        message = replay_chat_history(chat, msg_array)

        catch(:truncated) do
          response = chat.ask(message) do |chunk|
            # RubyLLM yields Chunk objects (inherits from Message)
            text = chunk.is_a?(String) ? chunk : chunk.content.to_s
            next if text.empty?

            # Populate reasoning_parts from thinking chunks if available
            reasoning_parts << chunk.thinking if chunk.respond_to?(:thinking) && chunk.thinking

            $stdout.print text
            $stdout.flush
            content_parts << text
            total_size += text.bytesize

            # Abort if response exceeds MAX_RESPONSE_SIZE
            if total_size > MAX_RESPONSE_SIZE
              Logging.warn("Response exceeds #{MAX_RESPONSE_SIZE} bytes, truncating")
              throw :truncated
            end
          end

          # Use final response object for token counts
          final_response = response
        end

        $stdout.puts

        response_data = {
          content: content_parts.join,
          reasoning: reasoning_parts.any? ? reasoning_parts.join : nil,
          model: model,
          tokens_in: final_response&.input_tokens || 0,
          tokens_out: final_response&.output_tokens || 0,
          cost: nil,
          finish_reason: "stop",
          streamed: true,
        }

        validate_response(response_data, model)
      rescue StandardError => err
        Result.err("ruby_llm streaming error: #{err.message}")
      end

      # True when this model is configured with api: replicate in models.yml
      def replicate_model?(model_id)
        cfg = configured_models_by_id[model_id]
        cfg&.dig(:api)&.to_s == "replicate"
      end

      # Execute text-generation via Replicate::LLM (bypass ruby_llm / OpenRouter)
      def execute_replicate_llm_request(prompt:, messages:, model:, reasoning:)
        require_relative "../replicate/llm"
        require_relative "../replicate/client"

        # Flatten messages + prompt into a single prompt string.
        # Replicate's predictions API uses a single prompt field, not a messages array.
        msg_array  = build_message_array(prompt, messages)
        sys_msg    = msg_array.find { |msg| msg[:role] == "system" }
        # Interleave user/assistant turns into a conversation-style prompt
        turns = msg_array.reject { |msg| msg[:role] == "system" }
        flat_prompt = if turns.size == 1
                        turns.first[:content]
                      else
                        turns.map { |msg| "#{msg[:role].capitalize}: #{msg[:content]}" }.join("\n\n")
                      end

        system_prompt = sys_msg&.dig(:content)

        # Reasoning budget hint → increase max_tokens for reasoning models
        max_tokens = reasoning ? 8_192 : Replicate::LLM::DEFAULT_MAX_TOKENS

        Replicate::LLM.complete(
          model,
          flat_prompt,
          system_prompt: system_prompt,
          max_tokens: max_tokens,
        )
      rescue StandardError => err
        Result.err("Replicate LLM request failed: #{err.message}", category: :infrastructure)
      end

      public

      # Response validation with proper checks
      def validate_response(data, model_id)
        content = data[:content]
        if content.nil? || (content.is_a?(String) && content.strip.empty?)
          return Result.err("Empty response from #{extract_model_name(model_id)}")
        end

        data[:tokens_in] = 0 unless data[:tokens_in].is_a?(Integer) || data[:tokens_in].is_a?(Float)

        data[:tokens_out] = 0 unless data[:tokens_out].is_a?(Integer) || data[:tokens_out].is_a?(Float)

        data[:cost] = nil if data[:cost] && !data[:cost].is_a?(Numeric)

        Result.ok(data)
      end
    end
  end
end
