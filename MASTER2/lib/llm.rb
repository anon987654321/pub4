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
    TIER_ORDER = %i[premium strong fast cheap free].freeze
    REASONING_EFFORT = %i[none minimal low medium high xhigh].freeze
    MAX_RESPONSE_SIZE = 5_000_000 # 5MB max for streaming
    MAX_CHAT_TOKENS = 8_192 # cap OpenRouter max_tokens reservation

    # Thread-safe ruby_llm configuration
    CONFIGURE_MUTEX = Mutex.new
    @ruby_llm_configured = false

    # Derived at runtime from models.yml tier:free + api:openrouter entries.
    # Replaces the old hardcoded stale list.
    def self.free_fallbacks
      configured_models
        .select { |m| m[:tier]&.to_s == "free" && m.dig(:api)&.to_s == "openrouter" }
        .map { |m| m[:id] }
        .freeze
    end

    class << self
      attr_accessor :current_model, :persona_prompt
      attr_reader :forced_model, :forced_tier

      # Tier setter for compatibility
      def tier=(value)
        @forced_tier = value.to_sym if value
      end

      # Force a specific model (set by `model` command).
      # When set, ask() uses this model directly instead of tier-based selection.
      def force_model!(model_id)
        @forced_model = model_id
        @forced_tier = classify_tier(model_id)
      end

      def clear_forced_model!
        @forced_model = nil
        @forced_tier = nil
      end

      def model_forced?
        !@forced_model.nil?
      end

      def api_key
        ENV.fetch("OPENROUTER_API_KEY", nil)
      end

      def replicate_api_key
        ENV["REPLICATE_API_TOKEN"] || ENV.fetch("REPLICATE_API_KEY", nil)
      end

      # Configured if either OpenRouter or Replicate API key is present
      def configured?
        (api_key && !api_key.empty?) || (replicate_api_key && !replicate_api_key.empty?)
      end

      def configured_for_openrouter?
        api_key && !api_key.empty?
      end

      def configured_for_replicate?
        replicate_api_key && !replicate_api_key.empty?
      end

      # Returns true when the model's api field in models.yml is "replicate".
      def replicate_model?(model_id)
        m = configured_models_by_id[model_id]
        m && m[:api].to_s == "replicate"
      end

      # Text-generation via Replicate, using Client.complete which:
      #   - builds model-family-aware input (anthropic vs deepseek vs default schema)
      #   - creates prediction via /v1/models/{owner}/{name}/predictions
      #   - polls until done and returns a normalised Result
      # This keeps llm.rb thin: all HTTP/polling logic stays in replicate/client.rb.
      def execute_replicate_llm_request(prompt:, messages:, model:, reasoning: nil)
        require_relative "replicate/client"

        unless Replicate.available?
          return Result.err("REPLICATE_API_TOKEN not set", category: :infrastructure)
        end

        sys = messages&.find { |m| m[:role] == "system" }
        system_prompt = sys&.dig(:content)

        opts = {}
        opts[:reasoning_effort] = reasoning[:effort].to_s if reasoning.is_a?(Hash) && reasoning[:effort]

        Replicate::Client.complete(model, prompt, system_prompt: system_prompt, **opts)
      end

      # Configure ruby_llm with thread safety (only needed for OpenRouter models)
      def configure_ruby_llm
        CONFIGURE_MUTEX.synchronize do
          return if @ruby_llm_configured

          RubyLLM.configure do |c|
            c.openrouter_api_key = api_key if api_key
          end
          @ruby_llm_configured = true
        end
      end

      # Check API key status
      def check_key
        return Result.err("No API key (set REPLICATE_API_TOKEN or OPENROUTER_API_KEY).") unless configured?

        configure_ruby_llm if configured_for_openrouter?
        label = [
          configured_for_replicate? ? "Replicate" : nil,
          configured_for_openrouter? ? "OpenRouter" : nil,
        ].compact.join(" + ")
        Result.ok(label: label)
      rescue StandardError => e
        Result.err("Key check failed: #{e.message}")
      end

      def tier
        return @forced_tier if @forced_tier

        :strong
      end

      def spending_cap
        Float::INFINITY
      end

      def budget_remaining
        Float::INFINITY
      end

      def record_cost(model:, tokens_in:, tokens_out:)
        0.0
      end

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
        unless configured?
          return Result.err("No API key — set REPLICATE_API_TOKEN or OPENROUTER_API_KEY.",
                            category: :infrastructure)
        end

        configure_ruby_llm if configured_for_openrouter?
        CircuitBreaker.check_rate_limit!

        cache_result = SemanticCache.lookup(prompt, tier: tier) if defined?(SemanticCache) && !stream
        return cache_result if cache_result&.ok?

        # Honor forced model override (set by `model` command).
        # When a user explicitly sets a model, use it instead of tier selection.
        if model.nil? && @forced_model
          model = @forced_model
          tier = @forced_tier || tier
        end

        primary = model || select_model(tier)
        return Result.err("No model available.", category: :infrastructure) unless primary

        @current_model = primary

        models_to_try = if fallbacks
                          [primary] + fallbacks
                        elsif configured_for_openrouter?
                          [primary] + free_fallbacks.reject { |m| m == primary }
                        else
                          [primary]
                        end
        last_error = nil

        models_to_try.each do |candidate_model|
          next unless CircuitBreaker.circuit_closed?(candidate_model)

          result = try_model(candidate_model, prompt, messages, reasoning, json_schema, provider, stream)

          if result.ok?
            process_llm_response(result, candidate_model, prompt, stream)
            if candidate_model != primary
              Logging.model_event(extract_model_name(candidate_model), "ok fallback") if defined?(Logging)
            else
              Logging.model_event(extract_model_name(candidate_model), "ok") if defined?(Logging)
            end
            return result
          else
            handle_llm_failure(result, candidate_model)
            # Demote fail events to ALL_EVENTS — hidden at default trace level, visible with MASTER_TRACE=2
            Logging.model_event(extract_model_name(candidate_model), "fail", result.error.to_s[0..40],
                                level: Logging::ALL_EVENTS) if defined?(Logging)
            last_error = result.error
          end
        end

        Result.err("all models exhausted: #{last_error}", category: :infrastructure)
      rescue StandardError => e
        CircuitBreaker.open_circuit!(primary) if primary
        Result.err(Logging.format_error(e), category: :infrastructure)
      end

      private

      LLM_WATCHDOG_SECS = (ENV["MASTER_LLM_TIMEOUT"] || 120).to_i

      def try_model(current_model, prompt, messages, reasoning, json_schema, provider, stream)
        spinner = nil
        unless stream || Thread.current[:llm_quiet]
          spinner = UI.spinner
          spinner.auto_spin
        end

        result     = nil
        timed_out  = false
        worker     = Thread.new do
          result = execute_with_retry(
            prompt: prompt, messages: messages, model: current_model,
            reasoning: reasoning, json_schema: json_schema,
            provider: provider, stream: stream
          )
        end

        unless worker.join(LLM_WATCHDOG_SECS)
          worker.kill
          timed_out = true
          result = Result.err("LLM timeout after #{LLM_WATCHDOG_SECS}s", category: :infrastructure)
        end

        result.ok? ? spinner&.success : spinner&.error
        result
      end

      def process_llm_response(result, current_model, prompt, stream)
        data = result.value
        tokens_in = data[:tokens_in]
        tokens_out = data[:tokens_out]
        cost = data[:cost] || 0.0

        if defined?(Logging)
          Logging.llm(tier: :default, model: @current_model, tokens_in: tokens_in, tokens_out: tokens_out,
                      cost: cost)
        end
        SemanticCache.store(prompt, data, tier: :default) if defined?(SemanticCache) && !stream
        CircuitBreaker.close_circuit!(current_model)

        # Publish LLM response event for interested subscribers
        if defined?(EventBus) && EventBus.respond_to?(:publish)
          EventBus.publish(:llm_response,
                           model: current_model,
                           tokens_in: tokens_in,
                           tokens_out: tokens_out,
                           cost: cost,
                           streamed: stream)
        end
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
        c = RubyLLM.chat(model: m, assume_model_exists: true, provider: :openrouter)
        if tools
          require_relative "llm/tools"
          c.with_tools(*MASTER::LLM::TOOL_CLASSES)
        end
        c
      end

      # A4: Multi-modal query with file attachments
      def ask_with_files(prompt, files:, model: nil)
        configure_ruby_llm
        m = model || select_model
        return Result.err("No model available.", category: :infrastructure) unless m

        c = RubyLLM.chat(model: m, assume_model_exists: true, provider: :openrouter)
        response = c.ask(prompt, with: files)
        Result.ok({
                    content: response.content,
                    tokens_in: response.input_tokens || 0,
                    tokens_out: response.output_tokens || 0,
                    cost: 0,
                  })
      rescue StandardError => e
        Result.err(e.message, category: :infrastructure)
      end

      # A6: Image generation (Replicate-only policy)
      def paint(prompt, model: nil)
        unless defined?(Replicate) && Replicate.available?
          return Result.err("Replicate API token required for media generation.")
        end

        Replicate.generate(prompt: prompt, model: model)
      end

      # A7: Audio transcription (Replicate-only policy)
      def transcribe(audio_path, model: nil)
        unless defined?(Replicate) && Replicate.available?
          return Result.err("Replicate API token required for media transcription.")
        end

        model_id = model || Replicate::MODELS[:whisper]
        Replicate.run(model_id: model_id, input: { audio: audio_path })
      end

      # A9: Structured output with ruby_llm Schema DSL
      def ask_structured(prompt, schema_class:, model: nil)
        configure_ruby_llm
        m = model || select_model
        c = RubyLLM.chat(model: m, assume_model_exists: true, provider: :openrouter).with_schema(schema_class)
        response = c.ask(prompt)
        Result.ok({ content: response.content, tokens_in: response.input_tokens || 0,
                    tokens_out: response.output_tokens || 0 })
      rescue StandardError => e
        Result.err(e.message)
      end

      # A12: Content moderation
      def moderate(text)
        configure_ruby_llm
        result = RubyLLM.moderate(text)
        Result.ok({ flagged: result.flagged?, categories: result.categories })
      rescue StandardError => e
        Result.err(e.message)
      end

      # Structured output helper - guarantees valid JSON matching schema
      def ask_json(prompt, schema:, tier: :fast, **)
        ask(prompt, tier: tier, json_schema: schema, **)
      end

      # Reasoning-enhanced query
      def ask_with_reasoning(prompt, effort: :medium, tier: :strong, **)
        ask(prompt, tier: tier, reasoning: { effort: effort }, **)
      end

      # Auto-router - let OpenRouter pick best model
      def ask_auto(prompt, **)
        ask(prompt, model: "openrouter/auto", **)
      end

      # Delegate circuit_closed? to CircuitBreaker for callers that use LLM.circuit_closed?
      def circuit_closed?(model)
        CircuitBreaker.circuit_closed?(model)
      end
    end
  end
end

require_relative "llm/models"
require_relative "llm/request"
require_relative "llm/context_window"
require_relative "replicate/llm"
require_relative "replicate/client"
