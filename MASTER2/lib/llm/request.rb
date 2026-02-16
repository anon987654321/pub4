# frozen_string_literal: true

module MASTER
  module LLM
    class << self
      private

      # Retry logic with exponential backoff (3 attempts, 1s/2s/4s delays)
      def execute_with_retry(prompt:, messages:, model:, reasoning:, json_schema:, provider:, stream:)
        max_retries = 3
        retry_count = 0
        last_error = nil

        while retry_count < max_retries
          begin
            result = execute_ruby_llm_request(
              prompt: prompt,
              messages: messages,
              model: model,
              reasoning: reasoning,
              json_schema: json_schema,
              provider: provider,
              stream: stream
            )

            # Success or non-retryable error
            return result if result.ok? || !retryable_error?(result.error)

            last_error = result.error
          rescue StandardError => e
            last_error = e.message
          end

          retry_count += 1
          break if retry_count >= max_retries

          # Exponential backoff: 1s, 2s, 4s
          sleep_time = 2 ** (retry_count - 1)
          Logging.warn("LLM retry #{retry_count}/#{max_retries}", delay: sleep_time, error: last_error)
          sleep(sleep_time)
        end

        Result.err("Failed after #{max_retries} retries: #{last_error}")
      end

      def retryable_error?(error)
        return false unless error.is_a?(String) || error.is_a?(Hash)
        error_str = error.is_a?(Hash) ? error[:message].to_s : error.to_s

        # Auto-reduce max_tokens on credit limit errors
        if error_str.match?(/can only afford (\d+)/i)
          affordable = error_str[/can only afford (\d+)/, 1].to_i
          Thread.current[:llm_max_tokens] = [affordable - 100, 512].max
          return true
        end

        error_str.match?(/timeout|connection|network|429|502|503|504|overloaded/i)
      end

      # Execute request using ruby_llm
      def execute_ruby_llm_request(prompt:, messages:, model:, reasoning:, json_schema:, provider:, stream:)
        configure_ruby_llm

        chat = RubyLLM.chat(model: model)
        cap = Thread.current[:llm_max_tokens] || MAX_CHAT_TOKENS
        chat = chat.with_params(max_tokens: cap)

        # Validate reasoning effort values
        if reasoning
          effort = reasoning.is_a?(Hash) ? reasoning[:effort] : reasoning
          effort_str = effort.to_s
          unless REASONING_EFFORT.map(&:to_s).include?(effort_str)
            return Result.err("Invalid reasoning effort: #{effort_str}. Must be one of: #{REASONING_EFFORT.join(', ')}")
          end
          chat = chat.with_thinking(effort: effort_str)
        end

        # JSON schema support
        if json_schema
          schema_data = json_schema[:schema] || json_schema
          chat = chat.with_json_schema(schema_data)
        end

        # Provider preferences
        if provider && provider.is_a?(Hash)
          chat = chat.with_params(provider: provider)
        end

        # Build proper message array for RubyLLM (preserves multi-turn conversations)
        msg_array = build_message_array(prompt, messages)

        # Extract system message if present (proper role separation)
        system_msg = msg_array.find { |m| m[:role] == "system" }
        if system_msg
          chat = chat.with_instructions(system_msg[:content])
          msg_array = msg_array.reject { |m| m[:role] == "system" }
        end

        # Execute query with proper message array
        if stream
          execute_streaming_ruby_llm(chat, msg_array, model)
        else
          execute_blocking_ruby_llm(chat, msg_array, model)
        end
      rescue StandardError => e
        Result.err(Logging.format_error(e))
      end

      # Build message array preserving full conversation history with proper role separation
      def build_message_array(prompt, messages)
        result = []

        if messages && messages.is_a?(Array) && !messages.empty?
          # Convert existing messages to proper format
          messages.each do |m|
            role = (m[:role] || m["role"]).to_s
            content = m[:content] || m["content"]
            next unless content
            result << { role: role, content: content }
          end
        end

        # Add current prompt as user message if provided
        if prompt && !prompt.to_s.empty?
          result << { role: "user", content: prompt.to_s }
        end

        result
      end

      # Prepare message for RubyLLM chat API
      def prepare_chat_message(msg_array)
        if msg_array.is_a?(Array)
          return "" if msg_array.empty?

          if msg_array.size > 1
            # Multi-turn conversation: use array form
            msg_array
          else
            # Single message: extract content safely
            first_msg = msg_array.first
            first_msg.is_a?(Hash) ? (first_msg[:content] || first_msg["content"] || "") : ""
          end
        else
          # Fallback to string
          msg_array.to_s
        end
      end

      def execute_blocking_ruby_llm(chat, msg_array, model)
        # RubyLLM supports both string and message array
        message = prepare_chat_message(msg_array)
        response = chat.ask(message)

        response_data = {
          content: response.content,
          reasoning: (response.thinking if response.respond_to?(:thinking)),
          model: model,
          tokens_in: response.input_tokens || 0,
          tokens_out: response.output_tokens || 0,
          cost: nil,
          finish_reason: "stop"
        }

        validate_response(response_data, model)
      rescue StandardError => e
        Result.err("ruby_llm error: #{e.message}")
      end

      # Streaming with size limits and proper token counts
      def execute_streaming_ruby_llm(chat, msg_array, model)
        content_parts = []
        reasoning_parts = []
        total_size = 0
        final_response = nil

        # RubyLLM supports both string and message array
        message = prepare_chat_message(msg_array)
        response = chat.ask(message) do |chunk|
          # RubyLLM yields Chunk objects (inherits from Message)
          text = chunk.is_a?(String) ? chunk : chunk.content.to_s
          next if text.empty?

          $stderr.print text
          content_parts << text
          total_size += text.bytesize

          # Abort if response exceeds MAX_RESPONSE_SIZE
          if total_size > MAX_RESPONSE_SIZE
            Logging.warn("Response exceeds #{MAX_RESPONSE_SIZE} bytes, truncating")
            break
          end
        end

        # Use final response object for token counts
        final_response = response

        $stderr.puts

        response_data = {
          content: content_parts.join,
          reasoning: reasoning_parts.any? ? reasoning_parts.join : nil,
          model: model,
          tokens_in: final_response.input_tokens || 0,
          tokens_out: final_response.output_tokens || 0,
          cost: nil,
          finish_reason: "stop",
          streamed: true
        }

        validate_response(response_data, model)
      rescue StandardError => e
        Result.err("ruby_llm streaming error: #{e.message}")
      end

      public

      # Response validation with proper checks
      def validate_response(data, model_id)
        content = data[:content]
        if content.nil? || (content.is_a?(String) && content.strip.empty?)
          return Result.err("Empty response from #{extract_model_name(model_id)}")
        end

        unless data[:tokens_in].is_a?(Integer) || data[:tokens_in].is_a?(Float)
          data[:tokens_in] = 0
        end

        unless data[:tokens_out].is_a?(Integer) || data[:tokens_out].is_a?(Float)
          data[:tokens_out] = 0
        end

        if data[:cost] && !data[:cost].is_a?(Numeric)
          data[:cost] = nil
        end

        Result.ok(data)
      end
    end
  end
end
