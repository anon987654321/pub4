# frozen_string_literal: true

module MASTER
  # Autonomy - enables MASTER to operate with minimal user intervention
  # Implements: auto-approval, retries, fallbacks, budget guards, circuit breakers
  module Autonomy
    extend self

    # Configuration defaults
    DEFAULT_CONFIG = {
      auto_approve_tools: true,
      confidence_threshold: 0.7,
      max_retries: 3,
      retry_delay: 1.0,
      budget_limit: 10.0,          # USD
      circuit_breaker_threshold: 5,
      circuit_breaker_reset: 300,  # seconds
      timeout_recovery: true,
      context_prune_threshold: 0.85,  # prune at 85% of token limit
      parallel_tools: true
    }.freeze

    # Circuit breaker state per provider
    @circuit_state = {}
    @total_cost = 0.0
    @tool_successes = Hash.new(0)
    @tool_failures = Hash.new(0)

    class << self
      attr_accessor :config, :total_cost

      def configure
        @config ||= DEFAULT_CONFIG.dup
        yield @config if block_given?
        @config
      end

      # 1. Tool auto-approval - skip confirmation for trusted operations
      def auto_approve?(tool_name, action)
        return false unless config[:auto_approve_tools]

        # Always approve read-only operations
        read_only = %w[scan analyze check lint view read list describe]
        return true if read_only.any? { |op| action.to_s.include?(op) }

        # Check tool success rate (approve if > 90% success)
        total = @tool_successes[tool_name] + @tool_failures[tool_name]
        return true if total > 10 && (@tool_successes[tool_name].to_f / total) > 0.9

        false
      end

      def record_tool_result(tool_name, success)
        if success
          @tool_successes[tool_name] += 1
        else
          @tool_failures[tool_name] += 1
        end
      end

      # 3. Confidence thresholds - retry if result confidence too low
      def meets_confidence?(result, threshold = nil)
        threshold ||= config[:confidence_threshold]
        confidence = extract_confidence(result)
        confidence >= threshold
      end

      def extract_confidence(result)
        return result[:confidence] if result.is_a?(Hash) && result[:confidence]
        return result.confidence if result.respond_to?(:confidence)

        # Heuristic: longer, more detailed responses = higher confidence
        text = result.to_s
        return 0.9 if text.length > 500 && !text.include?('unsure') && !text.include?('maybe')
        return 0.5 if text.include?('I think') || text.include?('possibly')
        return 0.3 if text.include?("I don't know") || text.include?('cannot')

        0.7  # default
      end

      # 4. Fallback strategies - model tier fallback chain
      FALLBACK_CHAIN = %w[
        anthropic/claude-sonnet-4-20250514
        anthropic/claude-3-5-haiku-20241022
        google/gemini-2.0-flash-001
        openai/gpt-4o-mini
      ].freeze

      def fallback_model(current_model)
        idx = FALLBACK_CHAIN.index(current_model)
        return FALLBACK_CHAIN.first unless idx

        FALLBACK_CHAIN[idx + 1] || FALLBACK_CHAIN.last
      end

      # 5. Budget guardrails
      def within_budget?(cost = 0)
        (@total_cost + cost) <= config[:budget_limit]
      end

      def track_cost(cost)
        @total_cost += cost
        Dmesg.budget('spent', cost, remaining_budget) rescue nil
        !exceeded_budget?
      end

      def exceeded_budget?
        @total_cost >= config[:budget_limit]
      end

      def remaining_budget
        [config[:budget_limit] - @total_cost, 0].max
      end

      # Estimate cost for a prompt (rough)
      def estimate_cost(prompt, response_estimate: 500)
        input_tokens = prompt.to_s.length / 4
        output_tokens = response_estimate
        # Default to Sonnet pricing
        (input_tokens * 3.0 / 1_000_000) + (output_tokens * 15.0 / 1_000_000)
      end

      # 6. Retry logic with exponential backoff
      def with_retry(max_retries: nil, &block)
        max_retries ||= config[:max_retries]
        attempt = 0

        loop do
          attempt += 1
          Dmesg.retry_event(attempt, max_retries, 'executing') rescue nil
          result = yield
          return result if result_ok?(result)

          break if attempt >= max_retries

          delay = config[:retry_delay] * (2 ** (attempt - 1))
          sleep(delay)
        end

        Result.err("Failed after #{max_retries} retries")
      end

      def result_ok?(result)
        return result.ok? if result.respond_to?(:ok?)
        return !result.nil? && result != false

        true
      end

      # 7. Circuit breaker - stop calling failing providers
      def circuit_open?(provider)
        state = @circuit_state[provider]
        return false unless state

        if state[:open] && (Time.now - state[:opened_at]) > config[:circuit_breaker_reset]
          # Half-open: allow one request to test
          state[:half_open] = true
          return false
        end

        state[:open]
      end

      def record_provider_result(provider, success)
        @circuit_state[provider] ||= { failures: 0, open: false }
        state = @circuit_state[provider]

        if success
          state[:failures] = 0
          state[:open] = false
          state[:half_open] = false
        else
          state[:failures] += 1
          if state[:failures] >= config[:circuit_breaker_threshold]
            state[:open] = true
            state[:opened_at] = Time.now
            Dmesg.circuit(provider, 'OPEN - too many failures') rescue nil
          end
        end
      end

      def reset_circuit(provider)
        @circuit_state.delete(provider)
      end

      # 8. Timeout recovery - retry with shorter context
      def timeout_recovery_context(messages, reduction: 0.5)
        return messages if messages.size <= 2

        # Keep system prompt + last N messages
        keep_count = [(messages.size * reduction).to_i, 2].max
        [messages.first] + messages.last(keep_count - 1)
      end

      # 9. Context pruning - auto-truncate when approaching limit
      def prune_context(messages, token_limit:, current_tokens:)
        threshold = token_limit * config[:context_prune_threshold]
        return messages if current_tokens < threshold

        # Summarize middle messages, keep first (system) and recent
        keep_recent = 10
        return messages if messages.size <= keep_recent + 1

        system = messages.first
        recent = messages.last(keep_recent)
        middle = messages[1..-(keep_recent + 1)]

        # Compress middle into summary
        summary = {
          role: 'system',
          content: "[Previous #{middle.size} messages summarized: Discussion covered #{extract_topics(middle)}]"
        }

        [system, summary] + recent
      end

      def extract_topics(messages)
        # Simple keyword extraction
        text = messages.map { |m| m[:content].to_s }.join(' ')
        words = text.downcase.scan(/\b[a-z]{4,}\b/)
        words.tally.sort_by { |_, v| -v }.first(5).map(&:first).join(', ')
      end

      # 10. Parallel tool execution
      def execute_parallel(tools, &block)
        return tools.map(&block) unless config[:parallel_tools]

        threads = tools.map do |tool|
          Thread.new { block.call(tool) }
        end

        threads.map(&:value)
      end

      # Reset all state
      def reset!
        @circuit_state = {}
        @total_cost = 0.0
        @tool_successes = Hash.new(0)
        @tool_failures = Hash.new(0)
        @config = DEFAULT_CONFIG.dup
      end
    end

    # Initialize with defaults
    @config = DEFAULT_CONFIG.dup
  end
end
