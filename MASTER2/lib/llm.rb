# frozen_string_literal: true

require "net/http"
require "json"
require "yaml"
require "uri"
require_relative "circuit_breaker"

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
    CHAT_ENDPOINT = "#{API_BASE}/chat/completions"

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
        selected_tier = model_rates[primary.split(":" ).first]&.[](:tier) || tier || :unknown

        # Update current state for prompt display
        @current_model = model_short
        @current_tier = selected_tier

        Dmesg.llm(selected_tier, model_short, tokens_in: 0, tokens_out: 0) if defined?(Dmesg)

        # Build request body
        body = build_request_body(
          prompt: prompt,
          messages: messages,
          model: primary,
          fallbacks: fallbacks,
          reasoning: reasoning,
          json_schema: json_schema,
          provider: provider,
          stream: stream
        )

        # Execute request
        spinner = nil
        unless stream
          spinner = UI.spinner("#{model_short}")
          spinner.auto_spin
        end

        result = execute_request(body, stream: stream)

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

      def build_request_body(prompt:, messages:, model:, fallbacks:, reasoning:, json_schema:, provider:, stream:)
        body = { model: model, stream: stream }

        # Messages
        body[:messages] = messages || [{ role: "user", content: prompt }]

        # Model fallbacks
        body[:models] = fallbacks if fallbacks&.any?

        # Reasoning tokens
        if reasoning
          body[:reasoning] = case reasoning
                             when Symbol
                               { effort: reasoning.to_s }
                             when Hash
                               reasoning.transform_keys(&:to_s)
                             else
                               { effort: "medium" }
                             end
        end

        # Structured outputs
        if json_schema
          body[:response_format] = {
            type: "json_schema",
            json_schema: {
              name: json_schema[:name] || "response",
              strict: true,
              schema: json_schema[:schema] || json_schema
            }
          }
        end

        # Provider preferences
        body[:provider] = provider if provider

        body
      end

      def execute_request(body, stream: false)
        uri = URI(CHAT_ENDPOINT)
        req = Net::HTTP::Post.new(uri)
        req["Authorization"] = "Bearer #{api_key}"
        req["Content-Type"] = "application/json"
        req["HTTP-Referer"] = "https://github.com/MASTER"
        req["X-Title"] = "MASTER Pipeline"

        req.body = body.to_json

        # Retry with exponential backoff
        max_retries = 3
        retry_count = 0
        last_error = nil

        while retry_count < max_retries
          begin
            http = Net::HTTP.new(uri.hostname, uri.port)
            http.use_ssl = true
            http.open_timeout = 30
            http.read_timeout = 120
            http.write_timeout = 30

            result = if stream
                       execute_streaming(http, req)
                     else
                       execute_blocking(http, req)
                     end

            # Success or non-retryable error
            return result if result.ok? || !retryable_error?(result.error)
            
            last_error = result.error
          rescue Net::OpenTimeout, Net::ReadTimeout, Errno::ECONNREFUSED, Errno::EHOSTUNREACH => e
            last_error = e.message
          end

          retry_count += 1

          # Exponential backoff: 1s, 2s, 4s
          sleep_time = 2 ** (retry_count - 1)
          Logging.warn("LLM retry #{retry_count}/#{max_retries}", delay: sleep_time, error: last_error) if defined?(Logging)
          sleep(sleep_time)
        end

        Result.err("Failed after #{max_retries} retries: #{last_error}")
      end

      def retryable_error?(error)
        return false unless error.is_a?(String)
        error.match?(/timeout|connection|network|429|502|503|504|overloaded/i)
      end

      def execute_blocking(http, req)
        response = http.request(req)

        unless response.code == "200"
          error_body = JSON.parse(response.body) rescue {}
          return Result.err(error_body["error"]&.[]("message") || "HTTP #{response.code}")
        end

        data = JSON.parse(response.body, symbolize_names: true)
        choice = data[:choices]&.first
        message = choice&.[](:message)

        response_data = {
          content: message&.[](:content),
          reasoning: message&.[](:reasoning),
          model: data[:model],
          tokens_in: data.dig(:usage, :prompt_tokens) || 0,
          tokens_out: data.dig(:usage, :completion_tokens) || 0,
          cost: data.dig(:usage, :cost),
          finish_reason: choice&.[](:finish_reason)
        }

        validate_response(response_data, req.body ? JSON.parse(req.body)[:model] : "unknown")
      rescue JSON::ParserError => e
        Result.err("JSON parse error: #{e.message}")
      end

      def execute_streaming(http, req)
        content_parts = []
        reasoning_parts = []
        final_data = {}

        http.request(req) do |response|
          unless response.code == "200"
            error_body = response.read_body
            parsed = JSON.parse(error_body) rescue {}
            return Result.err(parsed.dig("error", "message") || "HTTP #{response.code}")
          end

          response.read_body do |chunk|
            chunk.each_line do |line|
              next unless line.start_with?("data: ")
              json_str = line[6..]
              next if json_str.strip == "[DONE]"

              begin
                data = JSON.parse(json_str, symbolize_names: true)
                delta = data.dig(:choices, 0, :delta)

                if delta
                  if delta[:content]
                    $stderr.print delta[:content]
                    content_parts << delta[:content]
                  end
                  if delta[:reasoning]
                    reasoning_parts << delta[:reasoning]
                  end
                end

                # Capture final usage data
                if data[:usage]
                  final_data[:tokens_in] = data[:usage][:prompt_tokens]
                  final_data[:tokens_out] = data[:usage][:completion_tokens]
                  final_data[:cost] = data[:usage][:cost]
                end
                final_data[:model] = data[:model] if data[:model]
              rescue JSON::ParserError
                next
              end
            end
          end
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
end