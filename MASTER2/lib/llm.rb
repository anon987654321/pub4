# frozen_string_literal: true

require "ruby_llm"
require "json"
require "yaml"
require "stoplight"

# Configure RubyLLM with OpenRouter
RubyLLM.configure do |c|
  c.openrouter_api_key = ENV.fetch("OPENROUTER_API_KEY", nil)
end

module MASTER
  # LLM - OpenRouter API with fallbacks, reasoning, structured outputs
  # Features: model fallbacks, reasoning tokens, structured outputs, provider shortcuts
  module LLM
    MODELS_FILE = File.join(__dir__, "..", "data", "models.yml")
    BUDGET_FILE = File.join(__dir__, "..", "data", "budget.yml")
    TIER_ORDER = %i[premium strong fast cheap].freeze
    SPENDING_CAP = 10.0
    MAX_COST_PER_QUERY = 0.50   # Max cost per single query (except premium)

    # OpenRouter API
    API_BASE = "https://openrouter.ai/api/v1"
    API_KEY_CHECK = "#{API_BASE}/key"

    # Reasoning effort levels (OpenRouter normalized)
    REASONING_EFFORT = %i[none minimal low medium high xhigh].freeze

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
        @models ||= load_models
      end

      def load_models
        return [] unless File.exist?(MODELS_FILE)
        YAML.safe_load_file(MODELS_FILE, symbolize_names: true) || []
      end

      def reload_models
        @models = nil
        @model_tiers = nil
        @model_rates = nil
        @context_limits = nil
        @budget_thresholds = nil
        models
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

      # Check API key status and remaining credits
      def check_key
        return Result.err("No API key") unless configured?

        require "net/http"
        require "uri"
        
        uri = URI(API_KEY_CHECK)
        req = Net::HTTP::Get.new(uri)
        req["Authorization"] = "Bearer #{api_key}"

        http = Net::HTTP.new(uri.hostname, uri.port)
        http.use_ssl = true
        http.open_timeout = 10
        http.read_timeout = 30
        response = http.request(req)

        return Result.err("API error: #{response.code}") unless response.code == "200"

        data = JSON.parse(response.body, symbolize_names: true)[:data]
        return Result.err("Invalid API response") unless data

        Result.ok(
          label: data[:label],
          limit: data[:limit],
          remaining: data[:limit_remaining],
          usage: data[:usage],
          is_free_tier: data[:is_free_tier]
        )
      rescue Net::OpenTimeout, Net::ReadTimeout
        Result.err("API key check timed out")
      rescue StandardError => e
        Result.err("Key check failed: #{e.message}")
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

        # Rate limit check
        CircuitBreaker.check_rate_limit!

        # Cost firewall - abort if cumulative spend exceeds cap
        if total_spent >= SPENDING_CAP
          return Result.err("Budget exhausted: $#{total_spent.round(2)}/$#{SPENDING_CAP}. Session terminated.")
        end

        # Model selection (single call - no TOCTOU)
        primary = model || select_model_for_tier(tier || self.tier)
        return Result.err("No model available") unless primary

        # Pre-query cost estimate
        if model_rates[primary]
          est_cost = estimate_cost(primary, tokens_in: 1000, tokens_out: 500)
          if est_cost > MAX_COST_PER_QUERY
            return Result.err("Estimated cost $#{est_cost.round(2)} exceeds per-query limit $#{MAX_COST_PER_QUERY}")
          end
        end

        # Apply suffix shortcuts
        primary = apply_suffix(primary, online: online, provider: provider)

        model_short = extract_model_name(primary)
        selected_tier = model_rates[primary.split(":").first]&.[](:tier) || tier || :unknown

        # Update current state for prompt display
        @current_model = model_short
        @current_tier = selected_tier

        Dmesg.llm(selected_tier, model_short, tokens_in: 0, tokens_out: 0) if defined?(Dmesg)

        # Execute request
        spinner = nil
        unless stream
          spinner = UI.spinner("#{model_short}")
          spinner.auto_spin
        end

        result = execute_request_ruby_llm(
          prompt: prompt,
          messages: messages,
          model: primary,
          fallbacks: fallbacks,
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
          cost = data[:cost] || record_cost(model: primary, tokens_in: tokens_in, tokens_out: tokens_out)

          Dmesg.llm(selected_tier, model_short, tokens_in: tokens_in, tokens_out: tokens_out, cost: cost) if defined?(Dmesg)

          CircuitBreaker.close_circuit!(primary)
          Result.ok(data)
        else
          spinner&.error
          CircuitBreaker.open_circuit!(primary)
          Dmesg.llm_error(selected_tier, result.error) if defined?(Dmesg)
          result
        end
      rescue StandardError => e
        spinner&.error rescue nil
        CircuitBreaker.open_circuit!(primary) if primary
        Result.err("LLM error: #{e.message}")
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

      def apply_suffix(model, online: false, provider: nil)
        suffixes = []
        suffixes << ":online" if online
        suffixes << ":nitro" if provider&.dig(:sort) == "throughput"
        suffixes << ":floor" if provider&.dig(:sort) == "price"

        return model if suffixes.empty?
        "#{model}#{suffixes.first}"  # Only one suffix allowed
      end

      def execute_request_ruby_llm(prompt:, messages:, model:, fallbacks:, reasoning:, json_schema:, provider:, stream:)
        # Create chat instance
        chat = RubyLLM.chat(provider: :openrouter, model: model, assume_model_exists: true)

        # Apply params
        params = {}
        params[:models] = fallbacks if fallbacks&.any?
        params[:provider] = provider if provider

        # Apply reasoning
        if reasoning
          params[:reasoning] = case reasoning
                               when Symbol
                                 { effort: reasoning.to_s }
                               when Hash
                                 reasoning.transform_keys(&:to_s)
                               else
                                 { effort: "medium" }
                               end
        end

        # Apply structured outputs
        if json_schema
          params[:response_format] = {
            type: "json_schema",
            json_schema: {
              name: json_schema[:name] || "response",
              strict: true,
              schema: json_schema[:schema] || json_schema
            }
          }
        end

        chat = chat.with_params(**params) unless params.empty?

        # Prepare messages
        msgs = messages || [{ role: "user", content: prompt }]

        # Execute request
        if stream
          execute_streaming_ruby_llm(chat, msgs)
        else
          execute_blocking_ruby_llm(chat, msgs)
        end
      rescue StandardError => e
        Result.err("Request failed: #{e.message}")
      end

      def execute_blocking_ruby_llm(chat, messages)
        response = chat.ask(messages)

        # Extract response data
        content = response.content
        reasoning_text = nil
        # Check if response has reasoning method
        reasoning_text = response.reasoning if response.respond_to?(:reasoning)
        
        tokens_in = response.usage&.prompt_tokens || 0
        tokens_out = response.usage&.completion_tokens || 0
        cost = response.usage&.cost

        response_data = {
          content: content,
          reasoning: reasoning_text,
          model: response.model.id,
          tokens_in: tokens_in,
          tokens_out: tokens_out,
          cost: cost,
          finish_reason: response.finish_reason
        }

        validate_response(response_data, response.model.id)
      rescue StandardError => e
        Result.err("Request failed: #{e.message}")
      end

      def execute_streaming_ruby_llm(chat, messages)
        content_parts = []
        reasoning_parts = []
        final_data = {}

        chat.ask(messages) do |chunk|
          if chunk.content
            $stderr.print chunk.content
            content_parts << chunk.content
          end
          
          # Check if chunk has reasoning
          if chunk.respond_to?(:reasoning) && chunk.reasoning
            reasoning_parts << chunk.reasoning
          end

          # Capture final usage data
          if chunk.usage
            final_data[:tokens_in] = chunk.usage.prompt_tokens
            final_data[:tokens_out] = chunk.usage.completion_tokens
            final_data[:cost] = chunk.usage.cost
          end
          final_data[:model] = chunk.model.id if chunk.model
        end

        $stderr.puts

        final_data = {
          content: content_parts.join,
          reasoning: reasoning_parts.any? ? reasoning_parts.join : nil,
          model: final_data[:model],
          tokens_in: final_data[:tokens_in] || 0,
          tokens_out: final_data[:tokens_out] || 0,
          cost: final_data[:cost],
          finish_reason: "stop"
        }

        validate_response(final_data, "streaming")
      rescue StandardError => e
        Result.err("Streaming failed: #{e.message}")
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
        base_model = model.split(":").first  # Remove suffixes
        rates = model_rates.fetch(base_model, { in: 1.0, out: 1.0 })
        cost = (tokens_in * rates[:in] + tokens_out * rates[:out]) / 1_000_000.0
        DB.log_cost(model: base_model, tokens_in: tokens_in, tokens_out: tokens_out, cost: cost) if defined?(DB)
        cost
      end

      def estimate_cost(model, tokens_in:, tokens_out: 500)
        # Only the new signature — remove legacy path entirely
        rates = model_rates[model] || { in: 1.0, out: 2.0 }
        (tokens_in / 1_000_000.0 * rates[:in]) + (tokens_out / 1_000_000.0 * rates[:out])
      end

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

        if data[:cost] && !(data[:cost].is_a?(Numeric))
          data[:cost] = nil
        end

        Result.ok(data)
      end
    end
  end

  # CircuitBreaker - Rate limiting and failure handling for LLM calls
  # Prevents cascading failures and manages request throttling
  # Uses stoplight gem for circuit breaker functionality
  module CircuitBreaker
    extend self

    FAILURES_BEFORE_TRIP = 3
    CIRCUIT_RESET_SECONDS = 300
    RATE_LIMIT_PER_MINUTE = 30

    # Rate limiting state
    def rate_limit_state
      @rate_limit_state ||= { requests: [], window_start: Time.now }
    end

    def check_rate_limit!
      @rate_limit_mutex ||= Mutex.new
      @rate_limit_mutex.synchronize do
        now = Time.now
        state = rate_limit_state
        
        # Clean old requests (older than 1 minute)
        state[:requests].reject! { |t| now - t > 60 }
        
        if state[:requests].size >= RATE_LIMIT_PER_MINUTE
          oldest = state[:requests].min
          wait_time = 60 - (now - oldest)
          if wait_time > 0
            Logging.warn("Rate limit reached, waiting", seconds: wait_time.round) if defined?(Logging)
            sleep(wait_time)
            state[:requests].clear
          end
        end
        
        state[:requests] << now
      end
    end

    def run(model, &block)
      check_rate_limit!
      
      # Use Stoplight for circuit breaker
      light = Stoplight("llm-#{model}")
        .with_threshold(FAILURES_BEFORE_TRIP)
        .with_cool_off_time(CIRCUIT_RESET_SECONDS)
      
      light.run(&block)
    end

    def circuit_closed?(model)
      light = Stoplight("llm-#{model}")
        .with_threshold(FAILURES_BEFORE_TRIP)
        .with_cool_off_time(CIRCUIT_RESET_SECONDS)
      
      # Green = closed, yellow = half-open (testing), red = open (tripped)
      color = light.color
      color == "green" || color == "yellow"
    end

    # Compatibility methods for old API
    def open_circuit!(model)
      # Record a failure to trip the circuit
      # Stoplight manages state automatically based on failures
      log_warning("Circuit breaker triggered", model: model)
    end

    def close_circuit!(model)
      # In Stoplight, circuits close automatically after cool-off
      # We don't need to do anything here
    end
    
    private
    
    def log_warning(message, **args)
      if defined?(Logging)
        Logging.warn(message, **args)
      else
        # Fallback to stderr if Logging not available
        warn "#{message}: #{args.inspect}"
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