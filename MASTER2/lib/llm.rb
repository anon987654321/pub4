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

    FREE_FALLBACKS = %w[
      deepseek/deepseek-r1-0528:free
      deepseek/deepseek-chat:free
      google/gemini-2.0-flash-thinking-exp:free
      meta-llama/llama-3.1-8b-instruct:free
    ].freeze

    class << self
      attr_accessor :current_model, :persona_prompt
      attr_reader :forced_model

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
      rescue StandardError => err
        Result.err("Key check failed: #{err.message}")
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
                        else
                          [primary] + FREE_FALLBACKS.reject { |model_id| model_id == primary }
                        end
        last_error = nil

        models_to_try.each do |candidate_model|
          next unless CircuitBreaker.circuit_closed?(candidate_model)

          result = try_model(candidate_model, prompt, messages, reasoning, json_schema, provider, stream)

          if result.ok?
            process_llm_response(result, candidate_model, prompt, stream)
            $stderr.puts UI.dim("models0: #{extract_model_name(candidate_model)}") if candidate_model != primary
            return result
          else
            handle_llm_failure(result, candidate_model)
            last_error = result.error
          end
        end

        Result.err("all models exhausted: #{last_error}", category: :infrastructure)
      rescue StandardError => err
        CircuitBreaker.open_circuit!(primary) if primary
        Result.err(Logging.format_error(err), category: :infrastructure)
      end

      private

      def try_model(current_model, prompt, messages, reasoning, json_schema, provider, stream)
        spinner = nil
        # Replicate never streams (blocking poll) — always show spinner so the user
        # knows something is happening even when stream: true was requested.
        use_spinner = !Thread.current[:llm_quiet] && (!stream || replicate_model?(current_model))
        if use_spinner
          spinner = UI.spinner
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
        response_data = result.value
        tokens_in = response_data[:tokens_in]
        tokens_out = response_data[:tokens_out]
        cost = response_data[:cost] || 0.0

        if defined?(Logging)
          Logging.llm(tier: :default, model: @current_model, tokens_in: tokens_in, tokens_out: tokens_out,
                      cost: cost)
        end
        SemanticCache.store(prompt, response_data, tier: :default) if defined?(SemanticCache) && !stream
        CircuitBreaker.close_circuit!(current_model)

        # Publish LLM response event for interested subscribers
        if defined?(EventBus)
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
        # Credit exhaustion is permanent for this session — trip all OpenRouter models at once.
        if result.error.to_s.match?(/insufficient credits|can only afford|requires more credits/i)
          FREE_FALLBACKS.each { |model_id| CircuitBreaker.open_circuit!(model_id) }
        end
        Logging.llm_error(tier: :default, error: result.error) if defined?(Logging)
      end

      public

      # A3: Convenience method for creating a chat instance with optional tools
      def chat(model: nil, tools: false)
        configure_ruby_llm
        selected = model || select_model
        chat_session = RubyLLM.chat(model: selected, assume_model_exists: true, provider: :openrouter)
        if tools
          require_relative "llm/tools"
          chat_session.with_tools(*MASTER::LLM::TOOL_CLASSES)
        end
        chat_session
      end

      # A4: Multi-modal query with file attachments
      def ask_with_files(prompt, files:, model: nil)
        configure_ruby_llm
        selected = model || select_model
        return Result.err("No model available.", category: :infrastructure) unless selected

        chat_session = RubyLLM.chat(model: selected, assume_model_exists: true, provider: :openrouter)
        response = chat_session.ask(prompt, with: files)
        Result.ok({
                    content: response.content,
                    tokens_in: response.input_tokens || 0,
                    tokens_out: response.output_tokens || 0,
                    cost: 0,
                  })
      rescue StandardError => err
        Result.err(err.message, category: :infrastructure)
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
        selected = model || select_model
        chat_session = RubyLLM.chat(model: selected, assume_model_exists: true, provider: :openrouter).with_schema(schema_class)
        response = chat_session.ask(prompt)
        Result.ok({ content: response.content, tokens_in: response.input_tokens || 0,
                    tokens_out: response.output_tokens || 0 })
      rescue StandardError => err
        Result.err(err.message)
      end

      # A12: Content moderation
      def moderate(text)
        configure_ruby_llm
        result = RubyLLM.moderate(text)
        Result.ok({ flagged: result.flagged?, categories: result.categories })
      rescue StandardError => err
        Result.err(err.message)
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

      private

      # Retry logic with exponential backoff (3 attempts, 1s/2s/4s delays)
      EXECUTE_MAX_RETRIES = 3
      BACKOFF_BASE = 2

      def execute_with_retry(prompt:, messages:, model:, reasoning:, json_schema:, provider:, stream:)
        retry_count = 0
        last_error  = nil

        while retry_count < EXECUTE_MAX_RETRIES
          begin
            result = if replicate_model?(model)
                       execute_replicate_llm_request(prompt: prompt, messages: messages, model: model, reasoning: reasoning)
                     else
                       execute_ruby_llm_request(prompt: prompt, messages: messages, model: model,
                                                reasoning: reasoning, json_schema: json_schema,
                                                provider: provider, stream: stream)
                     end
            return result if result.ok? || !retryable_error?(result.error)

            last_error = result.error
          rescue ArgumentError => err
            return Result.err("ArgumentError: #{err.message}")
          rescue StandardError => err
            last_error = err.message
          end

          retry_count += 1
          break if retry_count >= EXECUTE_MAX_RETRIES

          sleep_time = BACKOFF_BASE**(retry_count - 1)
          Logging.warn("LLM retry #{retry_count}/#{EXECUTE_MAX_RETRIES}", delay: sleep_time, error: last_error)
          sleep(sleep_time)
        end

        Result.err("Failed after #{EXECUTE_MAX_RETRIES} retries: #{last_error}")
      end

      def retryable_error?(error)
        return false unless error.is_a?(String) || error.is_a?(Hash)

        error_str = error.is_a?(Hash) ? error[:message].to_s : error.to_s

        if error_str.match?(/Prompt tokens limit exceeded: (\d+) > (\d+)/i)
          Logging.warn("Prompt too large — clear history with /clear", subsystem: "llm.context")
          return false
        end

        if error_str.match?(/requires more credits|can only afford|insufficient credits/i)
          Logging.warn("Insufficient OpenRouter credits — add credits at openrouter.ai/settings/credits or use a free model: `model deepseek-r1-free`", subsystem: "llm.budget")
          return false
        end

        error_str.match?(/timeout|connection|network|429|502|503|504|overloaded/i)
      end

      def execute_ruby_llm_request(prompt:, messages:, model:, reasoning:, json_schema:, provider:, stream:)
        configure_ruby_llm
        chat = RubyLLM.chat(model: model, assume_model_exists: true, provider: :openrouter)
                      .with_params(max_tokens: LLM::MAX_CHAT_TOKENS)

        if reasoning
          effort     = reasoning.is_a?(Hash) ? reasoning[:effort] : reasoning
          effort_str = effort.to_s
          unless REASONING_EFFORT.map(&:to_s).include?(effort_str)
            return Result.err("Invalid reasoning effort: #{effort_str}. Must be one of: #{REASONING_EFFORT.join(', ')}")
          end
          chat = chat.with_thinking(effort: effort_str.to_sym)
        end

        chat = chat.with_schema(json_schema[:schema] || json_schema) if json_schema
        chat = chat.with_params(provider: provider)                   if provider.is_a?(Hash)

        msg_array  = build_message_array(prompt, messages)
        system_msg = msg_array.find { |msg| msg[:role] == "system" }
        if system_msg
          chat      = chat.with_instructions(system_msg[:content])
          msg_array = msg_array.reject { |msg| msg[:role] == "system" }
        end

        stream ? execute_streaming_ruby_llm(chat, msg_array, model)
               : execute_blocking_ruby_llm(chat, msg_array, model)
      rescue StandardError => err
        Result.err(Logging.format_error(err))
      end

      def build_message_array(prompt, messages)
        result = []
        if messages.is_a?(Array) && !messages.empty?
          messages.each do |msg|
            role    = (msg[:role] || msg["role"]).to_s
            content = msg[:content] || msg["content"]
            result << { role: role, content: content } if content
          end
        end
        result << { role: "user", content: prompt.to_s } if prompt && !prompt.to_s.empty?
        result
      end

      def replay_chat_history(chat, msg_array)
        return "" if msg_array.nil? || msg_array.empty?

        if msg_array.size > 1
          msg_array[0..-2].each do |msg|
            role    = msg[:role] || msg["role"]
            content = msg[:content] || msg["content"]
            chat.add_message(role: role.to_sym, content: content) if role && content
          end
        end

        final_msg = msg_array.last
        final_msg.is_a?(Hash) ? (final_msg[:content] || final_msg["content"] || "") : final_msg.to_s
      end

      def execute_blocking_ruby_llm(chat, msg_array, model)
        message  = replay_chat_history(chat, msg_array)
        response = chat.ask(message)
        validate_response({
          content:      response.content,
          reasoning:    (response.thinking if response.respond_to?(:thinking)),
          model:        model,
          tokens_in:    response.input_tokens  || 0,
          tokens_out:   response.output_tokens || 0,
          cost:         nil,
          finish_reason: "stop",
        }, model)
      rescue StandardError => err
        Result.err("ruby_llm error: #{err.message}")
      end

      def execute_streaming_ruby_llm(chat, msg_array, model)
        content_parts   = []
        reasoning_parts = []
        total_size      = 0
        final_response  = nil
        message         = replay_chat_history(chat, msg_array)

        catch(:truncated) do
          response = chat.ask(message) do |chunk|
            text = chunk.is_a?(String) ? chunk : chunk.content.to_s
            next if text.empty?

            reasoning_parts << chunk.thinking if chunk.respond_to?(:thinking) && chunk.thinking
            $stdout.print text
            $stdout.flush
            content_parts << text
            total_size    += text.bytesize
            if total_size > MAX_RESPONSE_SIZE
              Logging.warn("Response exceeds #{MAX_RESPONSE_SIZE} bytes, truncating")
              throw :truncated
            end
          end
          final_response = response
        end
        $stdout.puts

        validate_response({
          content:      content_parts.join,
          reasoning:    reasoning_parts.any? ? reasoning_parts.join : nil,
          model:        model,
          tokens_in:    final_response&.input_tokens  || 0,
          tokens_out:   final_response&.output_tokens || 0,
          cost:         nil,
          finish_reason: "stop",
          streamed:     true,
        }, model)
      rescue StandardError => err
        Result.err("ruby_llm streaming error: #{err.message}")
      end

      def replicate_model?(model_id)
        cfg = configured_models_by_id[model_id]
        cfg&.dig(:api)&.to_s == "replicate"
      end

      def execute_replicate_llm_request(prompt:, messages:, model:, reasoning:)
        msg_array   = build_message_array(prompt, messages)
        sys_msg     = msg_array.find { |msg| msg[:role] == "system" }
        turns       = msg_array.reject { |msg| msg[:role] == "system" }
        flat_prompt = turns.size == 1 ? turns.first[:content] : turns.map { |msg| "#{msg[:role].capitalize}: #{msg[:content]}" }.join("\n\n")

        Replicate::Client.complete(model, flat_prompt,
                                   system_prompt: sys_msg&.dig(:content),
                                   max_tokens:    reasoning ? 8_192 : Replicate::Client::DEFAULT_MAX_TOKENS)
      rescue StandardError => err
        Result.err("Replicate LLM request failed: #{err.message}", category: :infrastructure)
      end

      public

      def validate_response(data, model_id)
        content = data[:content]
        return Result.err("Empty response from #{extract_model_name(model_id)}") if content.nil? || (content.is_a?(String) && content.strip.empty?)

        data[:tokens_in]  = 0   unless data[:tokens_in].is_a?(Numeric)
        data[:tokens_out] = 0   unless data[:tokens_out].is_a?(Numeric)
        data[:cost]       = nil if data[:cost] && !data[:cost].is_a?(Numeric)
        Result.ok(data)
      end
    end
  end
end

require_relative "llm/models"
require_relative "llm/context_window"
require_relative "replicate/client"
