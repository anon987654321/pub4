# frozen_string_literal: true

require_relative 'workflow/planner'
require_relative 'workflow/engine'
require_relative 'workflow/convergence'
require_relative 'workflow/helper'

module MASTER
  # Backward compatibility aliases
  Planner = Workflow::Planner
  WorkflowEngine = Workflow::Engine
  Convergence = Workflow::Convergence
  Converge = Workflow::Convergence

  # Backward compatibility for PlannerHelper module
  PlannerHelper = Workflow::Helper
end
