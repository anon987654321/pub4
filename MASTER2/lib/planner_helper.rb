# frozen_string_literal: true

module MASTER
  # PlannerHelper - Lightweight plan generation (no execution)
  # Generates numbered step plans from goals
  # Complements existing Planner with standalone, reusable planning capability
  class PlannerHelper
    MAX_STEPS = 20

    def self.generate_plan(goal, llm: nil)
      new(llm: llm).generate_plan(goal)
    end

    def initialize(llm: nil)
      @llm = llm || LLM
    end

    # Generate a numbered plan from a goal
    # Returns Result with { steps: ["step 1", "step 2", ...] }
    def generate_plan(goal)
      prompt = build_planning_prompt(goal)
      
      result = @llm.ask(prompt, tier: :fast)
      return result unless result.ok?
      
      steps = parse_steps(result.value[:content])
      
      if steps.empty?
        Result.err("Failed to parse plan from LLM response")
      else
        Result.ok(steps: steps, raw: result.value[:content])
      end
    end

    private

    def build_planning_prompt(goal)
      <<~PROMPT
        Create a step-by-step plan to accomplish this goal.
        
        GOAL: #{goal}
        
        Requirements:
        - Break down into concrete, sequential steps
        - Number each step (1., 2., 3., etc.)
        - Make each step actionable and specific
        - Maximum #{MAX_STEPS} steps
        - Be concise and clear
        
        Format:
        1. [First step]
        2. [Second step]
        3. [Third step]
        ...
        
        PLAN:
      PROMPT
    end

    def parse_steps(text)
      steps = []
      
      text.lines.each do |line|
        # Match numbered items: "1. ", "2)", "1:", etc.
        if line =~ /^\s*(\d+)[.):\-]\s*(.+)/
          step_text = ::Regexp.last_match(2).strip
          next if step_text.empty?
          
          # Clean up common prefixes
          step_text = step_text.sub(/^(Step|Action|Task):\s*/i, '')
          
          steps << step_text
        end
      end
      
      steps.take(MAX_STEPS)
    end
  end
end
