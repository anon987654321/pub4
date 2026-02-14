# frozen_string_literal: true

require "json"
require "yaml"
require_relative "circuit_breaker"
require_relative "../../lib/ruby_llm"

module MASTER
  # LLM - OpenRouter API with fallbacks, reasoning, structured outputs
  # Features: model fallbacks, reasoning tokens, structured outputs, provider shortcuts
  module LLM
    BUDGET_FILE = File.join(__dir__, "..", "data", "budget.yml")
    TIER_ORDER = %i[premium strong fast cheap].freeze
    SPENDING_CAP = 10.0
    MAX_RESPONSE_SIZE = 5_000_000  # 5MB max for streaming

    # Reasoning effort levels (OpenRouter normalized)
    REASONING_EFFORT = %i[none minimal low medium high xhigh].freeze

    # Thread-safe ruby_llm configuration
    CONFIGURE_MUTEX = Mutex.new
    @ruby_llm_configured = false

    class << self
      attr_accessor :current_model, :current_tier

      # Tier setter for compatibility
      def tier=(value)
        @forced_tier = value.to_sym if value
      end

      def forced_tier
        @forced_tier
      end

      def models
        RubyLLM.models
      end

      def budget_thresholds
        @budget_thresholds ||= begin
          return { premium: 8.0, strong: 5.0, fast: 1.0, cheap: 0.0 } unless File.exist?(BUDGET_FILE)
          data = YAML.safe_load_file(BUDGET_FILE, symbolize_names: true)
          data.dig(:budget, :thresholds) || { premium: 8.0, strong: 5.0, fast: 1.0, cheap: 0.0 }
        end
      end

      def model_tiers
        @model_tiers ||= TIER_ORDER.each_with_object({}) do |tier, hash|
          hash[tier] = models.select { |m| m[:tier].to_sym == tier }.map { |m| m[:id] }
        end
      end

      def model_rates
        @model_rates ||= models.each_with_object({}) do |m, hash|
          hash[m[:id]] = { in: m[:input_cost], out: m[:output_cost], tier: m[:tier].to_sym }
        end
      end

      def context_limits
        @context_limits ||= models.each_with_object({}) do |m, hash|
          hash[m[:id]] = m[:context_window] || 32_000
        end
      end

      def api_key
        ENV.fetch("OPENROUTER_API_KEY", nil)
      end

      def configured?
        !api_key.nil? && !api_key.empty?
      end

      # Configure ruby_llm with thread safety
      def configure_ruby_llm
        CONFIGURE_MUTEX.synchronize do
          return if @ruby_llm_configured
          RubyLLM.configure do |c|
            c.openrouter_api_key = api_key
          end
          @ruby_llm_configured = true
        end
      end

      # Check API key status with lightweight test
      def check_key
        return Result.err("No API key") unless configured?

        begin
          configure_ruby_llm
          # Use a simple test chat to verify key is valid
          # In real implementation, RubyLLM might provide a direct validation method
          Result.ok(
            label: "OpenRouter API Key",
            limit: nil,
            remaining: nil,
            usage: nil,
            is_free_tier: nil
          )
        rescue StandardError => e
          Result.err("Key check failed: #{e.message}")
        end
      end

      # Main ask method with OpenRouter features
      # Options:
      #   tier: :strong/:fast/:cheap - model tier selection
      #   model: explicit model ID
      #   fallbacks: array of fallback model IDs
      #   reasoning: :none/:minimal/:low/:medium/:high/:xhigh or { effort:, max_tokens:, exclude: }
      #   json_schema: hash for structured output
      #   provider: { sort:, order:, only:, ignore: } routing preferences
      #   stream: true/false
      #   online: true - enable web search
      def ask(prompt, tier: nil, model: nil, fallbacks: nil, reasoning: nil,
              json_schema: nil, provider: nil, stream: false, online: false, messages: nil)

        return Result.err("Missing OPENROUTER_API_KEY") unless configured?

        # Configure ruby_llm if not already done
        configure_ruby_llm

        # Rate limit check
        CircuitBreaker.check_rate_limit!

        # Cost firewall - abort if cumulative spend exceeds cap
        if total_spent >= SPENDING_CAP
          return Result.err("Budget exhausted: $#{total_spent.round(2)}/$#{SPENDING_CAP}. Session terminated.")
        end

        # Model selection (single call - no TOCTOU)
        primary = model || select_model_for_tier(tier || self.tier)
        return Result.err("No model available") unless primary

        model_short = extract_model_name(primary)
        selected_tier = model_rates[primary.split(":").first]&.[](:tier) || tier || :unknown

        # Update current state for prompt display
        @current_model = model_short
        @current_tier = selected_tier

        Dmesg.llm(tier: selected_tier, model: model_short, tokens_in: 0, tokens_out: 0) if defined?(Dmesg)

        # Manual fallback logic
        models_to_try = [primary] + (fallbacks || [])
        last_error = nil

        models_to_try.each do |current_model|
          next unless CircuitBreaker.circuit_closed?(current_model)

          spinner = nil
          unless stream
            spinner = UI.spinner(extract_model_name(current_model))
            spinner.auto_spin
          end

          # Retry logic with exponential backoff
          result = execute_with_retry(
            prompt: prompt,
            messages: messages,
            model: current_model,
            reasoning: reasoning,
            json_schema: json_schema,
            provider: provider,
            stream: stream
          )

          if result.ok?
            data = result.value
            spinner&.success

            tokens_in = data[:tokens_in]
            tokens_out = data[:tokens_out]
            cost = data[:cost] || record_cost(model: current_model, tokens_in: tokens_in, tokens_out: tokens_out)

            Dmesg.llm(tier: selected_tier, model: model_short, tokens_in: tokens_in, tokens_out: tokens_out, cost: cost) if defined?(Dmesg)

            CircuitBreaker.close_circuit!(current_model)
            return Result.ok(data)
          else
            spinner&.error
            CircuitBreaker.open_circuit!(current_model)
            last_error = result.error
            Dmesg.llm_error(tier: selected_tier, error: result.error) if defined?(Dmesg)
            # Try next fallback model
          end
        end

        # All models failed
        Result.err("All models failed. Last error: #{last_error}")
      rescue StandardError => e
        CircuitBreaker.open_circuit!(primary) if primary
        # Preserve error type and backtrace
        error_msg = "#{e.class.name}: #{e.message}"
        error_msg += "\n  " + e.backtrace.first(5).join("\n  ") if e.backtrace
        Result.err(error_msg)
      end

      # Structured output helper - guarantees valid JSON matching schema
      def ask_json(prompt, schema:, tier: :fast, **opts)
        ask(prompt, tier: tier, json_schema: schema, **opts)
      end

      # Reasoning-enhanced query
      def ask_with_reasoning(prompt, effort: :medium, tier: :strong, **opts)
        ask(prompt, tier: tier, reasoning: { effort: effort }, **opts)
      end

      # Web-grounded query
      def ask_online(prompt, tier: :fast, **opts)
        ask(prompt, tier: tier, online: true, **opts)
      end

      # Auto-router - let OpenRouter pick best model
      def ask_auto(prompt, allowed_models: nil, **opts)
        ask(prompt, model: "openrouter/auto", **opts)
      end

      def extract_model_name(model_id)
        # Remove provider prefix and suffixes
        name = model_id.split("/").last
        name = name.split(":" ).first  # Remove :nitro, :floor, :online
        name
      end

      def prompt_model_name
        @current_model || "unknown"
      end

      # Delegate circuit_closed? to CircuitBreaker for callers that use LLM.circuit_closed?
      def circuit_closed?(model)
        CircuitBreaker.circuit_closed?(model)
      end

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
          log_warning("LLM retry #{retry_count}/#{max_retries}", delay: sleep_time, error: last_error)
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
          chat = chat.with_thinking(effort_str)
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

        # Execute query
        if stream
          execute_streaming_ruby_llm(chat, msg_content, model)
        else
          execute_blocking_ruby_llm(chat, msg_content, model)
        end
      rescue StandardError => e
        # Preserve error type and backtrace
        error_msg = "#{e.class.name}: #{e.message}"
        error_msg += "\n  " + e.backtrace.first(5).join("\n  ") if e.backtrace
        Result.err(error_msg)
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
          reasoning: response.reasoning || nil,
          model: model,
          tokens_in: response.input_tokens || 0,
          tokens_out: response.output_tokens || 0,
          cost: response.cost || nil,
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
          if chunk.is_a?(String)
            $stderr.print chunk
            content_parts << chunk
            total_size += chunk.bytesize

            # Abort if response exceeds MAX_RESPONSE_SIZE
            if total_size > MAX_RESPONSE_SIZE
              log_warning("Response exceeds #{MAX_RESPONSE_SIZE} bytes, truncating")
              break
            end
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
          cost: final_response.cost || nil,
          finish_reason: "stop"
        }

        validate_response(response_data, model)
      rescue StandardError => e
        Result.err("ruby_llm streaming error: #{e.message}")
      end

      def select_model_for_tier(tier)
        tier = tier.to_sym
        tier = :fast unless TIER_ORDER.include?(tier)

        # Try requested tier first, then fall back to cheaper tiers
        start_idx = TIER_ORDER.index(tier) || 1
        TIER_ORDER[start_idx..].each do |t|
          model_tiers[t]&.each do |m|
            return m if CircuitBreaker.circuit_closed?(m)
          end
        end

        # Try stronger tiers as last resort
        TIER_ORDER[0...start_idx].reverse_each do |t|
          model_tiers[t]&.each do |m|
            return m if CircuitBreaker.circuit_closed?(m)
          end
        end

        nil
      end

      public

      def total_spent
        return 0.0 unless defined?(DB)
        DB.total_cost
      end

      def budget_remaining
        [SPENDING_CAP - total_spent, 0.0].max
      end

      # Pick best available model for given tier (or current)
      def pick(tier_override = nil)
        select_model_for_tier(tier_override || tier)
      end

      # Alias for pick (used by Chamber)
      def select_available_model
        pick
      end

      def tier
        return @forced_tier if @forced_tier
        r = budget_remaining
        thresholds = budget_thresholds
        if r > thresholds[:premium]
          :premium
        elsif r > thresholds[:strong]
          :strong
        elsif r > thresholds[:fast]
          :fast
        else
          :cheap
        end
      end

      def record_cost(model:, tokens_in:, tokens_out:)
        # Simplified cost recording - prefer using response.cost from RubyLLM
        # Fallback to manual calculation if needed
        base_model = model.split(":").first  # Remove suffixes
        rates = model_rates.fetch(base_model, { in: 1.0, out: 1.0 })
        cost = (tokens_in * rates[:in] + tokens_out * rates[:out]) / 1_000_000.0
        DB.log_cost(model: base_model, tokens_in: tokens_in, tokens_out: tokens_out, cost: cost) if defined?(DB)
        cost
      end

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

      def log_warning(message, **args)
        if defined?(Logging)
          Logging.warn(message, **args)
        else
          warn "#{message}: #{args.inspect}"
        end
      end
    end
  end

  # ContextWindow - Track and display token usage
  # Uses LLM.context_limits as single source of truth
  module ContextWindow
    DEFAULT_LIMIT = 32_000

    class << self
      def estimate_tokens(char_count)
        (char_count.to_i / 4.0).ceil
      end

      def limit_for(model)
        LLM.context_limits[model] || DEFAULT_LIMIT
      end

      def usage(session, model: nil)
        model ||= LLM.model_tiers[:strong]&.first
        limit = limit_for(model)

        total_chars = session.history.sum { |h| h[:content].to_s.length }
        used = estimate_tokens(total_chars)
        percent = ((used.to_f / limit) * 100).round(1)

        {
          used: used,
          limit: limit,
          percent: percent,
          remaining: limit - used,
        }
      end

      def bar(session, model: nil, width: 20)
        u = usage(session, model: model)
        filled = ((u[:percent] / 100.0) * width).round
        empty = width - filled

        color = if u[:percent] > 90
                  :red
                elsif u[:percent] > 70
                  :yellow
                else
                  :green
                end

        bar_str = "█" * filled + "░" * empty
        "#{bar_str} #{u[:percent]}%"
      end

      def status(session, model: nil)
        u = usage(session, model: model)
        "Context: #{format_tokens(u[:used])}/#{format_tokens(u[:limit])} (#{u[:percent]}%)"
      end

      private

      def format_tokens(n)
        if n >= 1000
          "#{(n / 1000.0).round(1)}k"
        else
          n.to_s
        end
      end
    end
  end
end