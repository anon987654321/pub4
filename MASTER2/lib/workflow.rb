# frozen_string_literal: true

require 'yaml'
require 'time'

require_relative 'workflow/planner'
require_relative 'workflow/engine'
require_relative 'workflow/convergence'

module MASTER
  # Workflow - Unified workflow management combining planning, orchestration, and convergence detection
  # Consolidates: Planner + WorkflowEngine + Convergence for DRY and Single Responsibility
  module Workflow
  end

  # Backward compatibility alias
  Planner = Workflow::Planner
end
