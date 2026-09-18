# frozen_string_literal: true

module Master::Core::Execution
  # RoleManager — governs which model is currently active for a given role.
  #
  # It leverages the ModelRouter to resolve the best model for a role's task
  # and provides the ability to escalate roles (e.g., moving from a fast
  # implementer to a stronger one after repeated failures).
  class RoleManager
    attr_reader :router

    def initialize(router:, container:)
      @router = router
      @container = container
      @overrides = {}
    end

    # Resolves the model ID for a given role.
    # Priority: Manual Override -> Router Preference -> Default Model
    def model_for(role)
      return @overrides[role] if @overrides.key?(role)

      task_type = Roles::ROLE_TASK_MAP[role]
      return @router.preferred(task_type:) if task_type

      @router.preferred
    end

    def override(role, model_name)
      @overrides[role] = Master::Core::Routing::ModelCatalog.resolve(model_name)
    end

    def clear_override(role)
      @overrides.delete(role)
    end

    def active_roles
      Roles.constants.each_with_object({}) do |const, h|
        role = Roles.const_get(const)
        h[role] = model_for(role)
      end
    end
  end
end
