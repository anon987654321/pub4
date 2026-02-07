# frozen_string_literal: true

require "ruby_llm"
require "yaml"

module MASTER
  # LLM - Model selection, circuit breaker, cost tracking
  # Single source: data/models.yml
  module LLM
    MODELS_FILE = File.join(__dir__, "..", "data", "models.yml")
    TIER_ORDER = %i[strong fast cheap].freeze
    FAILURES_BEFORE_TRIP = 3
    CIRCUIT_RESET_SECONDS = 300
    SPENDING_CAP = 10.0

    class << self
      def models
        @models ||= load_models
      end

      def load_models
        return [] unless File.exist?(MODELS_FILE)
        YAML.safe_load_file(MODELS_FILE, symbolize_names: true) || []
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

      def configure
        RubyLLM.configure do |c|
          c.openrouter_api_key = ENV.fetch("OPENROUTER_API_KEY", nil)
        end
      end

      # Unified ask helper - handles model selection, circuit, cost
      def ask(prompt, model: nil, stream: true)
        model ||= select_available_model
        return Result.err("No model available") unless model
        return Result.err("Circuit open for #{model}") unless circuit_closed?(model)

        # TRANSPARENT_COST: estimate before execution
        estimated = estimate_cost(prompt.length, model)
        $stderr.puts "  [cost: ~#{format('$%.4f', estimated)}]" if estimated > 0.001

        chat_instance = chat(model: model)
        response = if stream
                     chat_instance.ask(prompt) { |chunk| $stderr.print chunk.content if chunk.content }
                   else
                     chat_instance.ask(prompt)
                   end
        $stderr.puts if stream

        tokens_in = response.input_tokens || 0
        tokens_out = response.output_tokens || 0
        cost = record_cost(model: model, tokens_in: tokens_in, tokens_out: tokens_out)
        close_circuit!(model)

        Result.ok(
          content: response.content,
          model: model,
          tokens_in: tokens_in,
          tokens_out: tokens_out,
          cost: cost,
        )
      rescue StandardError => e
        open_circuit!(model) if model
        Result.err("LLM error: #{e.message}")
      end

      def chat(model:)
        RubyLLM.chat(model: model)
      end

      def select_model(text_length = 0)
        desired = if text_length > 1000
                    :strong
                  elsif text_length > 200
                    :fast
                  else
                    :cheap
                  end
        start = [TIER_ORDER.index(desired), TIER_ORDER.index(tier)].max

        TIER_ORDER[start..].each do |t|
          model_tiers[t]&.each { |m| return { model: m, tier: t } if circuit_closed?(m) }
        end
        nil
      end

      def select_available_model
        result = select_model(500)
        result&.fetch(:model)
      end

      def circuit_closed?(model)
        row = DB.circuit(model)
        return true unless row

        state = row[:state]
        return true if state == "closed"

        last_failure = row[:last_failure]
        if Time.now.utc - Time.parse(last_failure) > CIRCUIT_RESET_SECONDS
          close_circuit!(model)
          true
        else
          false
        end
      end

      def open_circuit!(model)
        DB.trip!(model)
      end

      def close_circuit!(model)
        DB.reset!(model)
      end

      def total_spent
        DB.total_cost
      end

      def budget_remaining
        SPENDING_CAP - total_spent
      end

      def tier
        r = budget_remaining
        if r > 5.0
          :strong
        elsif r > 1.0
          :fast
        else
          :cheap
        end
      end

      def record_cost(model:, tokens_in:, tokens_out:)
        rates = model_rates.fetch(model, { in: 1.0, out: 1.0 })
        cost = (tokens_in * rates[:in] + tokens_out * rates[:out]) / 1_000_000.0
        DB.log_cost(model: model, tokens_in: tokens_in, tokens_out: tokens_out, cost: cost)
        cost
      end

      def estimate_cost(char_count, model)
        rates = model_rates.fetch(model, { in: 1.0, out: 1.0 })
        tokens_in = (char_count / 4.0).ceil
        tokens_out = 500  # estimate
        (tokens_in * rates[:in] + tokens_out * rates[:out]) / 1_000_000.0
      end
    end
  end
end
