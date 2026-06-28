# frozen_string_literal: true

module Master
  module Ground
    module ProviderRegistry
      LOCAL_FALLBACK = {
        local: { env: [], strengths: %i[privacy offline cheap], default_model: "local" },
      }.freeze

      module_function

      def providers
        @providers ||= load_providers
      end

      def available
        providers.select do |_name, provider_config|
          keys = Array(provider_config[:env])
          keys.empty? || keys.any? { |key| Master.api_key_present?(key) }
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
        raw = Master.provider_config
        raw.reject { |name, _config| name == "schema" }.to_h do |name, config|
          normalized = config.transform_keys(&:to_sym)
          normalized[:strengths] = Array(normalized[:strengths]).map(&:to_sym)
          [name.to_sym, normalized]
        end
      rescue StandardError => e
        Master::Ground::Swallow.log(e, context: "provider_registry.load")
        LOCAL_FALLBACK
      end

      def reset!
        @providers = nil
      end
    end
  end
end
