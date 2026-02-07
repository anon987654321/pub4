# frozen_string_literal: true

module MASTER
  # PlannerHelper - Helper for generating and parsing plans from LLM
  # Complements existing Planner module without conflicting
  module PlannerHelper
    extend self

    # Generate a numbered step plan from a goal string
    def generate_plan(goal, max_steps: 10)
      return Result.err("Goal cannot be empty") if goal.nil? || goal.empty?

      prompt = <<~PROMPT
        Create a step-by-step plan to accomplish this goal:
        
        GOAL: #{goal}
        
        Provide a numbered list of steps (maximum #{max_steps} steps).
        Each step should be clear and actionable.
        
        Format:
        1. First step
        2. Second step
        3. Third step
        ...
        
        PLAN:
      PROMPT

      if defined?(LLM)
        result = LLM.ask(prompt, tier: :fast)
        return result unless result.ok?
        
        steps = parse_plan(result.value[:content])
        Result.ok(steps: steps)
      else
        Result.err("LLM module not available")
      end
    end

    # Parse numbered steps from text into an array
    def parse_plan(text)
      return [] if text.nil? || text.empty?
      
      # Extract lines that start with numbers followed by period or parenthesis
      steps = text.scan(/^\s*(\d+)[.)]\s*(.+?)$/m).map { |_num, step| step.strip }
      
      # Remove empty steps
      steps.reject(&:empty?)
    end
  end
end
