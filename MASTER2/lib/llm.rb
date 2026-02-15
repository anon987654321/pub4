# frozen_string_literal: true

require "json"
require "yaml"
require_relative "circuit_breaker"
require "ruby_llm"

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
      attr_reader :persona_prompt

      # Tier setter for compatibility
      def tier=(value)
        @forced_tier = value.to_sym if value
      end

      def forced_tier
        @forced_tier
      end

      # Set persona prompt (called from Personas module)
      def persona_prompt=(value)
        @persona_prompt = value
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
        return Result.err("No API key.") unless configured?

        begin
          configure_ruby_llm
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

        return Result.err("Missing OPENROUTER_API_KEY.") unless configured?

        configure_ruby_llm
        CircuitBreaker.check_rate_limit!

        if total_spent >= spending_cap
          return Result.err("Budget exhausted: $#{total_spent.round(2)}/$#{spending_cap}.")
        end

        cache_result = SemanticCache.lookup(prompt, tier: tier) if defined?(SemanticCache) && !stream
        return cache_result if cache_result&.ok?

        primary = model || select_model
        return Result.err("No model available.") unless primary

        @current_model = extract_model_name(primary)

        # Auto-fallback: try all models in order
        models_to_try = if fallbacks
                          [primary] + fallbacks
                        else
                          remaining = all_models.reject { |m| m == primary }
                          [primary] + remaining
                        end
        last_error = nil

        models_to_try.each do |current_model|
          next unless CircuitBreaker.circuit_closed?(current_model)

          result = try_model(current_model, prompt, messages, reasoning, json_schema, provider, stream)

          if result.ok?
            process_llm_response(result, current_model, prompt, stream)
            return Result.ok(result.value)
          else
            handle_llm_failure(result, current_model)
            last_error = result.error
          end
        end

        Result.err("All models failed. Last error: #{last_error}")
      rescue StandardError => e
        CircuitBreaker.open_circuit!(primary) if primary
        Result.err(Logging.format_error(e))
      end

      private

      def resolve_model(model)
        primary = model || select_model
        return nil unless primary

        @current_model = extract_model_name(primary)
        primary
      end

      def try_model(current_model, prompt, messages, reasoning, json_schema, provider, stream)
        spinner = nil
        unless stream
          spinner = UI.spinner(extract_model_name(current_model))
          spinner.auto_spin
        end

        result = execute_with_retry(
          prompt: prompt, messages: messages, model: current_model,
          reasoning: reasoning, json_schema: json_schema,
          provider: provider, stream: stream
        )

        result.ok? ? spinner&.success : spinner&.error
        result
      end

      def process_llm_response(result, current_model, prompt, stream)
        data = result.value
        tokens_in = data[:tokens_in]
        tokens_out = data[:tokens_out]
        cost = data[:cost] || record_cost(model: current_model, tokens_in: tokens_in, tokens_out: tokens_out)

        Dmesg.llm(tier: :default, model: @current_model, tokens_in: tokens_in, tokens_out: tokens_out, cost: cost) if defined?(Dmesg)
        SemanticCache.store(prompt, data, tier: :default) if defined?(SemanticCache) && !stream
        CircuitBreaker.close_circuit!(current_model)
      end

      def handle_llm_failure(result, current_model)
        CircuitBreaker.open_circuit!(current_model)
        Dmesg.llm_error(tier: :default, error: result.error) if defined?(Dmesg)
      end

      public

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

      # Delegate circuit_closed? to CircuitBreaker for callers that use LLM.circuit_closed?
      def circuit_closed?(model)
        CircuitBreaker.circuit_closed?(model)
      end
    end
  end
end

require_relative "llm/models"
require_relative "llm/budget"
require_relative "llm/request"
require_relative "llm/context_window"