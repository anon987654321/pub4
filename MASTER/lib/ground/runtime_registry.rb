# frozen_string_literal: true

module Master
  module Ground
  # Collapses ProviderRegistry, ProviderHealth, and ProviderQuarantineManager into one call site (#396 item 2).
    class RuntimeRegistry
      def initialize(
        health: Now::Routing::ProviderHealth.new,
        quarantine: Now::Routing::ProviderQuarantineManager.new,
        event_bus: nil
      )
        @health = health
        @quarantine = quarantine
        @bus = event_bus
      end

      def choose(task: :coding)
        candidates = ProviderRegistry.available
        name, cfg, score = select_provider(scored_providers(provider_pool(candidates)), task)
        quarantined_list = quarantined_names(candidates)
        @bus&.publish("runtime:provider_chosen", provider: name, score:, task:)

        { provider: name, model: cfg[:default_model], score:, quarantined: quarantined_list }
      end

      def status
        ProviderRegistry.available.map do |name, cfg|
          {
            provider: name,
            model: cfg[:default_model],
            score: @health.score(name),
            quarantined: @quarantine.quarantined?(name),
            strengths: cfg[:strengths],
          }
        end
      end

      private

      def provider_pool(candidates)
        available = candidates.reject { |name, _config| @quarantine.quarantined?(name) }
        available.any? ? available : candidates
      end

      def scored_providers(pool)
        pool.map { |name, config| [name, config, @health.score(name)] }
            .sort_by { |_name, _config, score| -score }
      end

      def select_provider(scored, task)
        match = scored.find { |_name, config, _score| config[:strengths].include?(task.to_sym) }
        match || scored.first || local_fallback
      end

      def local_fallback
        config = ProviderRegistry.providers.fetch(:local, ProviderRegistry::LOCAL_FALLBACK[:local])
        [:local, config, 0.5]
      end

      def quarantined_names(candidates)
        candidates.keys.select { |name| @quarantine.quarantined?(name) }
      end
    end
  end
end
