# frozen_string_literal: true

module Master
  module Review
    class Agent
      module Roles
        # Mapping of role to model resolution logic.
        # This allows us to use different models for Architect, Implementer, and Validator.
        ROLE_MODELS = {
          architect: ->(agent) { agent.routed_models(task_type: :architecture).first },
          implementer: ->(agent) { agent.routed_models(task_type: :code_generation).first },
          validator: ->(agent) { agent.routed_models(task_type: :explanation).first },
        }.freeze

        def model_for_role(role)
          resolver = ROLE_MODELS[role.to_sym]
          raise ArgumentError, "unknown role: #{role}" unless resolver
          resolver.call(self)
        end
      end
    end
  end
end
