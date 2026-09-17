# frozen_string_literal: true

module Master::Core::Execution
  # Roles — a functional split between the different modes of reasoning
  # required to reach convergence.
  #
  # The Architect plans the change, the Implementer writes the code, and the
  # Validator verifies the outcome. Each role may be backed by a different
  # model identity, allowing MASTER to use the strongest reasoner for planning
  # and the most reliable tool-user for implementation.
  module Roles
    ARCHITECT = :architect
    IMPLEMENTER = :implementer
    VALIDATOR = :validator

    # Map roles to the current system's routing preferences.
    # This is the bridge to the ModelRouter's task-based routing.
    ROLE_TASK_MAP = {
      ARCHITECT => :architecture,
      IMPLEMENTER => :coding,
      VALIDATOR => :review,
    }.freeze
  end
end
