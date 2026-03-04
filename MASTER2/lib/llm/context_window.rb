# frozen_string_literal: true

module Llm
  class ContextWindow
    DEFAULT_MAX_TOKENS = 8_192
    DEFAULT_RESERVED_OUTPUT_TOKENS = 1_024
    DEFAULT_OVERHEAD_TOKENS = 50

    attr_reader :max_tokens, :reserved_output_tokens, :overhead_tokens

    def initialize(
      max_tokens: DEFAULT_MAX_TOKENS,
      reserved_output_tokens: DEFAULT_RESERVED_OUTPUT_TOKENS,
      overhead_tokens: DEFAULT_OVERHEAD_TOKENS,
      tokenizer: nil
    )
      @max_tokens = Integer(max_tokens)
      @reserved_output_tokens = Integer(reserved_output_tokens)
      @overhead_tokens = Integer(overhead_tokens)
      @tokenizer = tokenizer
    end

    def available_prompt_tokens
      [@max_tokens - @reserved_output_tokens - @overhead_tokens, 0].max
    end

    def fits?(messages, extra_tokens: 0)
      tokens_for_messages(messages) + Integer(extra_tokens) <= available_prompt_tokens
    end

    def trim(messages, extra_tokens: 0)
      extra_token_count = Integer(extra_tokens)
      budget = available_prompt_tokens - extra_token_count
      return [] if budget <= 0

      pruned_messages = Array(messages).dup
      while pruned_messages.any? && tokens_for_messages(pruned_messages) > budget
        pruned_messages.shift
      end
      pruned_messages
    end

    def tokens_for(text)
      return 0 if text.nil? || text == ""

      if @tokenizer
        @tokenizer.call(text)
      else
        approximate_tokens(text)
      end
    end

    def tokens_for_messages(messages)
      Array(messages).sum do |message|
        tokens_for(message_content(message)) + message_overhead_tokens(message)
      end
    end

    private

    def approximate_tokens(text)
      (text.to_s.length / 4.0).ceil
    end

    def message_content(message)
      case message
      when String
        message
      when Hash
        message[:content] || message["content"] || message.to_s
      else
        message.to_s
      end
    end

    def message_overhead_tokens(message)
      return 0 unless message.is_a?(Hash)

      role = message[:role] || message["role"]
      role ? 2 : 0
    end
  end
end