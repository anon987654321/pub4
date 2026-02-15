# frozen_string_literal: true

module MASTER
  module Workflow
    # PlannerHelper - Backward compatibility wrapper
    module Helper
      extend self

      def parse_plan(text)
        Planner.parse_plan(text)
      end

      def generate_plan(goal, max_steps: 10)
        Planner.generate_plan(goal, max_steps: max_steps)
      end
    end
  end
end
