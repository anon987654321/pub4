# frozen_string_literal: true

module Master
  module Ground
    # Lightweight shared behavior for the various *Policy modules in ground/.
    # Goal: reduce duplication across orchestration_policy, workflow_policy,
    # sandbox_policy, subagent_policy, tool_approval_policy, etc. (SINGULARITY + DENSITY).
    module Policy
      module_function

      def brief(description)
        "#{self.name}: #{description}"
      end
    end
  end
end
