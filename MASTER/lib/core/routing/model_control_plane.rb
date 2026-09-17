# frozen_string_literal: true

module Master::Core::Routing
  # ModelControlPlane — the central authority for model orchestration.
  #
  # It coordinates between the Catalog (what exists), the CapabilityMap
  # (how they perform), and the Router (how to pick one).
  class ModelControlPlane
    attr_reader :catalog, :capability_map, :router

    def initialize(catalog:, capability_map:, router:)
      @catalog = catalog
      @capability_map = capability_map
      @router = router
    end

    # Selects the optimal route based on task requirements and empirical data.
    def select_route(task_requirements:)
      # 1. Identify required capabilities
      # 2. Filter healthy models from Catalog
      # 3. Use CapabilityMap to find the best candidate
      # 4. Return a Route object (Plan)

      model_id = @router.preferred(task_type: task_requirements[:task_type])

      # In a full implementation, this would return a Route object containing:
      # - Primary model
      # - Fallback model
      # - Reviewer model
      # - Budget constraints
      {
        primary: model_id,
        rationale: "Selected based on empirical capability for #{task_requirements[:task_type]}",
        budget: task_requirements[:budget] || :default,
      }
    end

    def update_health(model_id, status, reason = nil)
      # Logic to trip circuit breakers if a model degrades
      # This would link to the ModelPassport's health state
    end
  end
end
