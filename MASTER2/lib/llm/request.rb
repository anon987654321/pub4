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
        error_str.match?(/timeout|connection|network|429|502|503|504|overloaded/i)
      end

      # Execute request using ruby_llm
      def execute_ruby_llm_request(prompt:, messages:, model:, reasoning:, json_schema:, provider:, stream:)
        configure_ruby_llm

        chat = RubyLLM.chat(model: model)

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

        # Preserve full message history
        msg_content = build_message_content(prompt, messages)

        # Extract system message if present (proper role separation)
        user_content = msg_content
        if msg_content.start_with?("[system]")
          parts = msg_content.split("\n\n[user] ", 2)
          if parts.size == 2
            system_text = parts[0].sub(/^\[system\]\s*/, "")
            user_content = parts[1]
            chat = chat.with_instructions(system_text)
          end
        end

        # Execute query
        if stream
          execute_streaming_ruby_llm(chat, user_content, model)
        else
          execute_blocking_ruby_llm(chat, user_content, model)
        end
      rescue StandardError => e
        Result.err(Logging.format_error(e))
      end

      # Build message content preserving full conversation history
      def build_message_content(prompt, messages)
        if messages && messages.is_a?(Array) && !messages.empty?
          history = messages.map do |m|
            role = (m[:role] || m["role"]).to_s
            content = m[:content] || m["content"]
            next unless content
            "[#{role}] #{content}"
          end.compact
          history << "[user] #{prompt}" if prompt && !prompt.to_s.empty?
          history.join("\n\n")
        else
          prompt.to_s
        end
      end

      def execute_blocking_ruby_llm(chat, content, model)
        response = chat.ask(content)

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
      def execute_streaming_ruby_llm(chat, content, model)
        content_parts = []
        reasoning_parts = []
        total_size = 0
        final_response = nil

        response = chat.ask(content) do |chunk|
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
