# frozen_string_literal: true

module MASTER
  class Executor
    module PreAct
      def execute_pre_act(goal, tier:)
        start_time = MASTER::Utils.monotonic_now

        UI.dim("  planning...")
        plan_result = generate_plan(goal, tier: tier)
        return plan_result unless plan_result.ok?

        @plan = plan_result.value[:steps]
        UI.dim("  #{@plan.size} steps")

        # Phase 2: Execute plan step by step
        results = []
        @plan.each_with_index do |planned_step, idx|
          return err if (err = timeout_error_for(start_time))

          @step = idx + 1
          UI.dim("  #{@step}/#{@plan.size}: #{planned_step[0..60]}")

          # Execute the planned action
          raw_observation = dispatch_action(planned_step)

          return err if (err = injection_error_for(raw_observation, source: "step #{@step}"))

          evidence_obj = ToolResult.normalize("shell_command", raw_observation)
          observation  = evidence_obj.to_prompt
          results << { step: @step, action: planned_step, observation: observation, evidence_hash: evidence_obj.content_hash }
          record_history(results.last)

          UI.dim("  = #{observation.lines.first.to_s.strip[0..80]}")

          next unless raw_observation.to_s.match?(/\bError\b|\bERROR\b|: error:|^error:/i) || raw_observation.to_s.include?("not found")

          UI.dim("  replanning...")
          replan_result = replan(goal, results, tier: tier)
          @plan = @plan[0..idx] + replan_result.value[:steps] if replan_result.ok? && replan_result.value[:steps].any?
        end

        # Phase 3: Synthesize final answer
        synthesize_answer(goal, results, tier: tier)
      end

      def generate_plan(goal, tier:)
        tool_list = Executor.tool_list_text

        prompt = Prompts.get(:preact, :generate_plan, goal: goal, tool_list: tool_list)

        result = LLM.ask(prompt, tier: tier)
        return result unless result.ok?

        # Parse numbered steps
        steps = result.value[:content].scan(/^\d+\.\s*(.+)$/m).flatten
        steps = steps.map(&:strip).reject(&:empty?)

        Result.ok(steps: steps)
      end

      def replan(goal, completed, tier:)
        history_text = completed.map { |r| "#{r[:action]} -> #{r[:observation][0..100]}" }.join("\n")

        prompt = Prompts.get(:preact, :replan, goal: goal, history: history_text)

        result = LLM.ask(prompt, tier: tier)
        return result unless result.ok?

        steps = result.value[:content].scan(/^\d+\.\s*(.+)$/m).flatten
        Result.ok(steps: steps.map(&:strip))
      end

      def synthesize_answer(goal, results, tier:)
        history_text = results.map { |r| "Step #{r[:step]}: #{r[:action]}\nResult: #{r[:observation][0..300]}" }.join("\n\n")

        prompt = Prompts.get(:preact, :synthesize, goal: goal, history: history_text)

        result = LLM.ask(prompt, tier: :fast)
        return result unless result.ok?

        Result.ok(
          answer: result.value[:content],
          steps: @step,
          pattern: :pre_act,
          plan: @plan,
          history: @history,
        )
      end
    end
  end
end
