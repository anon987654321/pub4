# frozen_string_literal: true

# Backward compatibility aliases
# Consolidates all legacy module/class aliases in one place per ONE_SOURCE axiom
# This file should be loaded last in the boot sequence

module MASTER
  # Workflow aliases (from lib/workflow.rb)
  Planner = Workflow::Planner
  WorkflowEngine = Workflow::Engine
  Convergence = Workflow::Convergence
  Converge = Workflow::Convergence

  # Backward compatibility for PlannerHelper module
  module PlannerHelper
    extend self

    def parse_plan(text)
      Workflow::Planner.parse_plan(text)
    end

    def generate_plan(goal, max_steps: 10)
      Workflow::Planner.generate_plan(goal, max_steps: max_steps)
    end
  end

  # Logging aliases (from lib/logging.rb)
  Log = Logging
  Dmesg = Logging

  # Bridge aliases (from lib/bridges.rb)
  PostproBridge = Bridges::PostproBridge
  RepligenBridge = Bridges::RepligenBridge

  # Analysis aliases (from lib/analysis.rb)
  Prescan = Analysis::Prescan
  Introspection = Analysis::Introspection
  SelfMap = Analysis::Introspection
  SelfCritique = Analysis::Introspection
  SelfRepair = Analysis::Introspection
  SelfTest = Analysis::Introspection

  # Hooks alias (from lib/hooks.rb)
  HooksManager = Hooks
end

# Review aliases (from lib/review.rb) - outside MASTER module
CodeReview = MASTER::Review::Scanner
AutoFixer = MASTER::Review::Fixer
Enforcement = MASTER::Review::Enforcer
QualityStandards = MASTER::Review::Enforcer
FileHygiene = MASTER::Review::Scanner::FileHygiene
