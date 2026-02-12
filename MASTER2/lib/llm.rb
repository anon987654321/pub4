# frozen_string_literal: true

require "ruby_llm"
require "json"
require "yaml"
require_relative "circuit_breaker"

module MASTER
  # LLM - OpenRouter API with fallbacks, reasoning, structured outputs
  # Features: model fallbacks, reasoning tokens, structured outputs, provider shortcuts
  # Now powered by ruby_llm gem instead of manual Net::HTTP
  module LLM
    MODELS_FILE = File.join(__dir__, "..", "data", "models.yml")
    BUDGET_FILE = File.join(__dir__, "..", "data", "budget.yml")
    TIER_ORDER = %i[premium strong fast cheap].freeze
    SPENDING_CAP = 10.0
    MAX_COST_PER_QUERY = 0.50   # Max cost per single query (except premium)

    # Reasoning effort levels (OpenRouter normalized)
    REASONING_EFFORT = %i[none minimal low medium high xhigh].freeze

    class << self
      attr_accessor :current_model, :current_tier

      # Initialize ruby_llm configuration
      def configure_ruby_llm
        return if @ruby_llm_configured
        
        RubyLLM.configure do |c|
          c.openrouter_api_key = ENV.fetch("OPENROUTER_API_KEY", nil)
        end
        
        @ruby_llm_configured = true
      end

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
        
        configure_ruby_llm
        
        begin
          # Use ruby_llm to check the key
          # Note: ruby_llm doesn't have a direct key check method, so we'll do a minimal request
          # or fall back to manual HTTP check
          require "net/http"
          require "uri"
          
          uri = URI("https://openrouter.ai/api/v1/auth/key")
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

        result = execute_with_ruby_llm(
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
        name = name.split(":").first  # Remove :nitro, :floor, :online
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

      def execute_with_ruby_llm(prompt:, messages:, model:, fallbacks:, reasoning:, json_schema:, provider:, stream:)
        # Build options hash for ruby_llm
        options = {}
        
        # Handle reasoning - use with_thinking for reasoning support
        if reasoning
          reasoning_params = case reasoning
                            when Symbol
                              { effort: reasoning.to_s }
                            when Hash
                              reasoning
                            else
                              { effort: "medium" }
                            end
          # Note: with_thinking uses effort or budget params
          options[:thinking_effort] = reasoning_params[:effort]
          options[:thinking_budget] = reasoning_params[:max_tokens] if reasoning_params[:max_tokens]
        end
        
        # Handle JSON schema
        if json_schema
          options[:schema] = json_schema[:schema] || json_schema
        end
        
        # Handle provider preferences (OpenRouter-specific)
        if provider
          # OpenRouter uses HTTP headers for provider preferences
          options[:provider_params] = provider
        end
        
        # Handle model fallbacks (OpenRouter-specific)
        if fallbacks&.any?
          # OpenRouter models parameter for fallbacks
          options[:fallback_models] = fallbacks
        end

        begin
          # Create chat instance
          chat = RubyLLM.chat(model: model)
          
          # Apply thinking if needed
          if options[:thinking_effort] || options[:thinking_budget]
            chat = chat.with_thinking(
              effort: options[:thinking_effort],
              budget: options[:thinking_budget]
            )
          end
          
          # Apply schema if needed
          chat = chat.with_schema(options[:schema]) if options[:schema]
          
          # Apply custom headers for OpenRouter provider preferences
          if options[:provider_params]
            # OpenRouter accepts provider params in request body, not headers
            # We'll need to use with_params to pass these through
            chat = chat.with_params(provider: options[:provider_params])
          end
          
          # Prepare messages - ruby_llm expects string for simple ask
          msg_content = messages || prompt
          
          # Execute with or without streaming
          if stream
            content_parts = []
            reasoning_parts = []
            final_tokens_in = 0
            final_tokens_out = 0
            final_model = model
            
            response = chat.ask(msg_content) do |chunk|
              # ruby_llm streaming - chunk is a Message/Chunk object
              if chunk.content
                $stderr.print chunk.content
                content_parts << chunk.content
              end
              
              if chunk.thinking&.text
                reasoning_parts << chunk.thinking.text
              end
              
              # Accumulate tokens from chunks
              final_tokens_in = chunk.input_tokens if chunk.input_tokens
              final_tokens_out = chunk.output_tokens if chunk.output_tokens
              final_model = chunk.model_id if chunk.model_id
            end
            
            $stderr.puts
            
            # Get final cost from response tokens
            Result.ok({
              content: content_parts.join,
              reasoning: reasoning_parts.any? ? reasoning_parts.join : nil,
              model: final_model,
              tokens_in: final_tokens_in,
              tokens_out: final_tokens_out,
              cost: nil,  # Cost will be calculated by record_cost
              finish_reason: "stop"
            })
          else
            # Blocking request
            response = chat.ask(msg_content)
            
            Result.ok({
              content: response.content || "",
              reasoning: response.thinking&.text,
              model: response.model_id || model,
              tokens_in: response.input_tokens || 0,
              tokens_out: response.output_tokens || 0,
              cost: nil,  # Cost will be calculated by record_cost
              finish_reason: "stop"
            })
          end
        rescue StandardError => e
          Result.err("RubyLLM error: #{e.message}")
        end
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
        rates = model_rates[model] || { in: 1.0, out: 2.0 }
        (tokens_in / 1_000_000.0 * rates[:in]) + (tokens_out / 1_000_000.0 * rates[:out])
      end
    end
  end
end
