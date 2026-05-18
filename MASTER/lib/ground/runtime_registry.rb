# frozen_string_literal: true

module Master
  module Ground
  # RuntimeRegistry — single source of truth for provider selection.
  # Issue #396 item 2: collapse duplicate orchestration registries.
  #
  # Combines ProviderRegistry (static capability map), ProviderHealth
  # (score telemetry), and ProviderQuarantineManager (availability) into
  # one call site. Callers ask choose() and get a live-aware selection.
  class RuntimeRegistry
    def initialize(
      health:     Now::Routing::ProviderHealth.new,
      quarantine: Now::Routing::ProviderQuarantineManager.new,
      event_bus:  nil
    )
      @health     = health
      @quarantine = quarantine
      @bus        = event_bus
    end

    # Return best provider for a task domain, respecting quarantine + scores.
    # Returns { provider: Symbol, model: String, score: Float, quarantined: [] }
    def choose(task: :coding)
      candidates = ProviderRegistry.available

      available = candidates.reject { |name, _| @quarantine.quarantined?(name) }
      pool      = available.any? ? available : candidates # fall back to full set if all quarantined

      scored = pool.map { |name, cfg| [name, cfg, @health.score(name)] }
                   .sort_by { |_, _, score| -score }

      # Prefer task-strength match over raw score
      match = scored.find { |_, cfg, _| cfg[:strengths].include?(task.to_sym) }
      name, cfg, score = match || scored.first || [:local, ProviderRegistry::PROVIDERS[:local], 0.5]

      quarantined_list = candidates.keys.select { |n| @quarantine.quarantined?(n) }
      @bus&.publish("runtime:provider_chosen", provider: name, score:, task:)

      { provider: name, model: cfg[:default_model], score:, quarantined: quarantined_list }
    end

    def status
      ProviderRegistry.available.map do |name, cfg|
        {
          provider:    name,
          model:       cfg[:default_model],
          score:       @health.score(name),
          quarantined: @quarantine.quarantined?(name),
          strengths:   cfg[:strengths]
        }
      end
    end
  end
  end
end
