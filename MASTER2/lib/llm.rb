# frozen_string_literal: true

require "json"
require "yaml"
require_relative "circuit_breaker"
require "ruby_llm"

module MASTER
  # LLM - OpenRouter API with fallbacks, reasoning, structured outputs
  # Policy: text/reasoning via OpenRouter; media generation/transcription via Replicate
  # Features: model fallbacks, reasoning tokens, structured outputs
  module LLM
    TIER_ORDER = %i[premium strong fast cheap].freeze
    MAX_RESPONSE_SIZE = 5_000_000  # 5MB max for streaming
    MAX_CHAT_TOKENS = 16_384

    # Thread-safe ruby_llm configuration
    CONFIGURE_MUTEX = Mutex.new
    @ruby_llm_configured = false

    class << self
      attr_accessor :current_model, :persona_prompt

      # Tier setter for compatibility
      def tier=(value)
        @forced_tier = value.to_sym if value
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
        configure_ruby_llm
        Result.ok(label: "OpenRouter API Key")
      rescue StandardError => e
        Result.err("Key check failed: #{e.message}")
      end

      # Stubs for backward compatibility (budgeting removed)
      def set_agent_budget(_budget); end
      def record_agent_cost(_cost); end

      # Ask LLM with fallbacks, reasoning, and structured outputs
      # Returns Result monad with value/error
      #
      # WARNING: CQS Violation - This query method mutates @current_model as a side effect
      # for tracking purposes (line 106). This is intentional but non-standard.
      #
      # Options:
      #   tier: :strong/:fast/:cheap - model tier selection (filters models by tier from models.yml)
      #   model: explicit model ID
      #   fallbacks: array of fallback model IDs
      #   reasoning: :none/:minimal/:low/:medium/:high/:xhigh or { effort:, max_tokens:, exclude: }
      #   json_schema: hash for structured output
      #   provider: { sort:, order:, only:, ignore: } routing preferences
      #   stream: true/false
      def ask(prompt, tier: nil, model: nil, fallbacks: nil, reasoning: nil,
              json_schema: nil, provider: nil, stream: false, messages: nil)

        return Result.err("Missing OPENROUTER_API_KEY.") unless configured?

        configure_ruby_llm
        CircuitBreaker.check_rate_limit!

        cache_result = SemanticCache.lookup(prompt, tier: tier) if defined?(SemanticCache) && !stream
        return cache_result if cache_result&.ok?

        primary = model || select_model(tier)
        return Result.err("No model available.") unless primary

        @current_model = primary

        # Auto-fallback: only cascade on infrastructure errors, max 2 retries
        models_to_try = if fallbacks
                          [primary] + fallbacks
                        else
                          [primary]
                        end
        last_error = nil

        models_to_try.each do |candidate_model|
          next unless CircuitBreaker.circuit_closed?(candidate_model)

          result = try_model(candidate_model, prompt, messages, reasoning, json_schema, provider, stream)

          if result.ok?
            process_llm_response(result, candidate_model, prompt, stream)
            return Result.ok(result.value)
          else
            handle_llm_failure(result, candidate_model)
            last_error = result.error
          end
        end

        Result.err("#{extract_model_name(primary)}: #{last_error}")
      rescue StandardError => e
        CircuitBreaker.open_circuit!(primary) if primary
        Result.err(Logging.format_error(e))
      end

      private

      def try_model(current_model, prompt, messages, reasoning, json_schema, provider, stream)
        spinner = nil
        unless stream || Thread.current[:llm_quiet]
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

        Logging.llm(tier: :default, model: @current_model, tokens_in: tokens_in, tokens_out: tokens_out, cost: cost) if defined?(Logging)
        SemanticCache.store(prompt, data, tier: :default) if defined?(SemanticCache) && !stream
        CircuitBreaker.close_circuit!(current_model)
      end

      def handle_llm_failure(result, current_model)
        CircuitBreaker.open_circuit!(current_model)
        Logging.llm_error(tier: :default, error: result.error) if defined?(Logging)
      end

      public

      # A3: Convenience method for creating a chat instance with optional tools
      def chat(model: nil, tools: false)
        configure_ruby_llm
        m = model || select_model
        c = RubyLLM.chat(model: m)
        if tools
          require_relative "llm/tools"
          c.with_tools(*MASTER::LLM::TOOL_CLASSES)
        end
        c
      end

      # A4: Multi-modal query with file attachments
      def ask_with_files(prompt, files:, model: nil, **opts)
        configure_ruby_llm
        m = model || select_model
        return Result.err("No model available.") unless m
        
        c = RubyLLM.chat(model: m)
        response = c.ask(prompt, with: files)
        Result.ok({
          content: response.content,
          tokens_in: response.input_tokens || 0,
          tokens_out: response.output_tokens || 0,
          cost: 0
        })
      rescue StandardError => e
        Result.err(e.message)
      end

      # A6: Image generation (Replicate-only policy)
      def paint(prompt, model: nil)
        return Result.err("Replicate API token required for media generation.") unless defined?(Replicate) && Replicate.available?

        Replicate.generate(prompt: prompt, model: model)
      end

      # A7: Audio transcription (Replicate-only policy)
      def transcribe(audio_path, model: nil)
        return Result.err("Replicate API token required for media transcription.") unless defined?(Replicate) && Replicate.available?

        model_id = model || Replicate::MODELS[:whisper]
        Replicate.run(model_id: model_id, input: { audio: audio_path })
      end

      # A9: Structured output with ruby_llm Schema DSL
      def ask_structured(prompt, schema_class:, model: nil, **opts)
        configure_ruby_llm
        m = model || select_model
        c = RubyLLM.chat(model: m).with_schema(schema_class)
        response = c.ask(prompt)
        Result.ok({ content: response.content, tokens_in: response.input_tokens || 0, tokens_out: response.output_tokens || 0 })
      rescue StandardError => e
        Result.err(e.message)
      end

      # A12: Content moderation
      def moderate(text)
        configure_ruby_llm
        begin
          result = RubyLLM.moderate(text)
          Result.ok({ flagged: result.flagged?, categories: result.categories })
        rescue StandardError => e
          Result.err(e.message)
        end
      end

      # Structured output helper - guarantees valid JSON matching schema
      def ask_json(prompt, schema:, tier: :fast, **opts)
        ask(prompt, tier: tier, json_schema: schema, **opts)
      end

      # Reasoning-enhanced query
      def ask_with_reasoning(prompt, effort: :medium, tier: :strong, **opts)
        ask(prompt, tier: tier, reasoning: { effort: effort }, **opts)
      end

      # Auto-router - let OpenRouter pick best model
      def ask_auto(prompt, **opts)
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
