# frozen_string_literal: true

module MASTER
  class Executor
    module PreAct
      def execute_pre_act(goal, tier:)
        UI.dim("  planning...")
        plan_result = generate_plan(goal, tier: tier)
        return plan_result unless plan_result.ok?

        @plan = plan_result.value[:steps]
        UI.dim("  #{@plan.size} steps")

        # Phase 2: Execute plan step by step
        results = []
        @plan.each_with_index do |planned_step, idx|
          @step = idx + 1
          UI.dim("  #{@step}/#{@plan.size}: #{planned_step[0..60]}")

          # Execute the planned action
          observation = execute_tool(planned_step)
          results << { step: @step, action: planned_step, observation: observation }
          record_history(results.last)

          UI.dim("  = #{observation[0..80]}")

          if observation.include?("error") || observation.include?("not found")
            UI.dim("  replanning...")
            replan_result = replan(goal, results, tier: tier)
            if replan_result.ok? && replan_result.value[:steps].any?
              @plan = @plan[0..idx] + replan_result.value[:steps]
            end
          end
        end

        # Phase 3: Synthesize final answer
        synthesize_answer(goal, results, tier: tier)
      end

      def generate_plan(goal, tier:)
        tool_list = TOOLS.map { |k, v| "  #{k}: #{v}" }.join("\n")

        prompt = <<~PLAN
          Create a step-by-step plan to accomplish this task:

          TASK: #{goal}

          TOOLS AVAILABLE:
          #{tool_list}

          Respond with a numbered list of tool invocations, one per line.
          Each step should be a complete tool command.

          Example:
          1. file_read "config.yml"
          2. analyze_code "src/main.rb"
          3. fix_code "src/main.rb"

          PLAN:
        PLAN

        result = LLM.ask(prompt, tier: tier)
        return result unless result.ok?

        # Parse numbered steps
        steps = result.value[:content].scan(/^\d+\.\s*(.+)$/m).flatten
        steps = steps.map(&:strip).reject(&:empty?)

        Result.ok(steps: steps)
      end

      def replan(goal, completed, tier:)
        history_text = completed.map { |r| "#{r[:action]} -> #{r[:observation][0..100]}" }.join("\n")

        prompt = <<~REPLAN
          Original task: #{goal}

          Completed steps:
          #{history_text}

          The last step had an unexpected result. What additional steps are needed?
          Respond with numbered tool commands only:
        REPLAN

        result = LLM.ask(prompt, tier: :fast)
        return result unless result.ok?

        steps = result.value[:content].scan(/^\d+\.\s*(.+)$/m).flatten
        Result.ok(steps: steps.map(&:strip))
      end

      def synthesize_answer(goal, results, tier:)
        history_text = results.map do |r|
          "Step #{r[:step]}: #{r[:action]}\nResult: #{r[:observation][0..300]}"
        end.join("\n\n")

        prompt = <<~SYNTH
          Task: #{goal}

          Execution results:
          #{history_text}

          Provide a concise final answer based on these results:
        SYNTH

        result = LLM.ask(prompt, tier: :fast)
        return result unless result.ok?

        Result.ok(
          answer: result.value[:content],
          steps: @step,
          pattern: :pre_act,
          plan: @plan,
          history: @history
        )
      end
    end

    # --- ReWOO pattern implementation ---
  end
end
