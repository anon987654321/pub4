# frozen_string_literal: true

module Master
  module Ground
    module ProviderRegistry
      DEFAULTS = {
        openai: {
          env: %w[OPENAI_API_KEY],
          strengths: %i[reasoning coding multimodal],
          default_model: "gpt-5.5-thinking",
        },
        anthropic: {
          env: %w[ANTHROPIC_API_KEY],
          strengths: %i[coding long_context instruction_following],
          default_model: "claude-sonnet-4-6",
        },
        gemini: {
          env: %w[GOOGLE_API_KEY GEMINI_API_KEY],
          strengths: %i[long_context multimodal],
          default_model: "gemini-2.5-flash",
        },
        openrouter: {
          env: %w[OPENROUTER_API_KEY],
          strengths: %i[cheap routing free_tier],
          default_model: "openrouter/auto",
        },
        deepseek: {
          env: %w[DEEPSEEK_API_KEY],
          strengths: %i[coding cheap],
          default_model: "deepseek-chat",
        },
        local: {
          env: [],
          strengths: %i[privacy offline cheap],
          default_model: "local",
        },
      }.freeze

      module_function

      def providers
        @providers ||= load_providers
      end

      def available
        providers.select do |_name, provider_config|
          Array(provider_config[:env]).empty? || provider_config[:env].any? { |key| ENV[key].to_s != "" }
        end
      end

      def choose(task: :coding)
        candidates = available
        exact = candidates.find { |_name, provider_config| provider_config[:strengths].include?(task.to_sym) }
        name, provider_config = exact || candidates.first || [:local, providers[:local]]
        { provider: name, model: provider_config[:default_model], strengths: provider_config[:strengths] }
      end

      def brief
        "Provider registry: available=#{available.keys.join(', ')}; choose by task strengths, fall back to local."
      end

      def load_providers
        path = File.join(Master::DATA, "providers.yml")
        return DEFAULTS unless File.exist?(path)
        Master.load_yaml(path).transform_keys(&:to_sym).transform_values do |v|
          v.transform_keys(&:to_sym).tap do |provider_config|
            provider_config[:strengths] = Array(provider_config[:strengths]).map(&:to_sym)
          end
        end
      rescue StandardError => e
        warn("provider_registry: #{e.message} — using defaults")
        DEFAULTS
      end
    end
  end
end
