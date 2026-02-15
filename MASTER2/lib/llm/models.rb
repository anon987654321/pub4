# frozen_string_literal: true

module MASTER
  module LLM
    class << self
      def models
        RubyLLM.models
      end

      def chat_models
        @chat_models ||= models.chat_models
      end

      def load_models_config
        @models_config ||= begin
          models_file = File.join(__dir__, "..", "..", "data", "models.yml")
          return [] unless File.exist?(models_file)
          begin
            YAML.safe_load_file(models_file, symbolize_names: true) || []
          rescue StandardError => e
            warn "Failed to load models.yml: #{e.message}"
            []
          end
        end
      end

      # Get curated models from models.yml
      def configured_models
        load_models_config
      end

      # Hash lookup for O(1) access to configured models by ID
      def configured_models_by_id
        @configured_models_by_id ||= configured_models.each_with_object({}) { |m, h| h[m[:id]] = m }
      end

      # Classify a model into a tier based on models.yml configuration
      def classify_tier(model)
        # For configured models, look up tier from models.yml with O(1) hash access
        return :cheap unless model.is_a?(String) || model&.id

        model_id = model.is_a?(String) ? model : model.id
        configured_model = configured_models_by_id[model_id]
        return configured_model[:tier].to_sym if configured_model&.dig(:tier)

        # Fallback to price-based classification for models not in models.yml
        price = model.is_a?(String) ? 0 : model.input_price_per_million || 0

        case price
        when (10.0..) then :premium
        when (2.0...10.0) then :strong
        when (0.1...2.0) then :fast
        else :cheap
        end
      end

      def model_tiers
        @model_tiers ||= TIER_ORDER.each_with_object({}) do |tier, hash|
          # Get models from models.yml for this tier (tier values are strings in YAML)
          hash[tier] = configured_models.select { |m| m[:tier].to_s == tier.to_s }.map { |m| m[:id] }
        end
      end

      def model_rates
        @model_rates ||= configured_models.each_with_object({}) do |m, hash|
          hash[m[:id]] = {
            in: m[:input_cost] || 0,
            out: m[:output_cost] || 0,
            tier: m[:tier]&.to_sym || :cheap
          }
        end
      end

      def context_limits
        @context_limits ||= configured_models.each_with_object({}) do |m, hash|
          hash[m[:id]] = m[:context_window] || 32_000
        end
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

      private

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
    end
  end
end
