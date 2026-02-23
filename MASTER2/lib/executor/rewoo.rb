# frozen_string_literal: true

module MASTER
  class Executor
    module ReWOO
      def execute_rewoo(goal, tier:)
        start_time = MASTER::Utils.monotonic_now

        tool_list = Executor.tool_list_text

        prompt = build_rewoo_prompt(goal, tool_list)

        UI.dim("  reasoning...")
        result = LLM.ask(prompt, tier: tier)
        return result unless result.ok?

        plan_text, actions = parse_rewoo_plan(result.value[:content])
        UI.dim("  #{actions.size} actions")

        evidence = execute_rewoo_steps(actions, start_time)
        return evidence unless evidence.is_a?(Hash) # Handle timeout error

        synthesize_rewoo(goal, plan_text, evidence)
      end

      private

      def build_rewoo_prompt(goal, tool_list)
        Prompts.get(:rewoo, :plan, goal: goal, tool_list: tool_list)
      end

      def parse_rewoo_plan(content)
        plan_text = content[/Plan:\s*(.+?)(?=#E1|$)/mi, 1]&.strip
        actions = content.scan(/#E(\d+)\s*=\s*(.+)$/i)
        [plan_text, actions]
      end

      def execute_rewoo_steps(actions, start_time)
        evidence = {}
        actions.each do |num, action_str|
          begin
            check_timeout!(start_time)
          rescue Result::Error => err
            return Result.err(err.message)
          end

          @step = num.to_i
          resolved = action_str.gsub(/#E(\d+)/) { evidence[::Regexp.last_match(1).to_i] || "" }

          UI.dim("  #E#{num}: #{resolved[0..60]}")
          observation = dispatch_action(resolved.strip)

          # Injection defense: halt on detected injection (gist item #3)
          if defined?(Security::Sanitizer) && !Security::Sanitizer.safe?(observation)
            return Result.err(
              "Injection attempt detected in tool response at #E#{num}. Aborting.",
              category: :validation,
            )
          end

          evidence[num.to_i] = observation
          record_history({ step: @step, action: resolved, observation: observation })
          UI.dim("  = #{observation[0..60]}")
        end
        evidence
      end

      def synthesize_rewoo(goal, plan_text, evidence)
        evidence_text = evidence.map { |k, v| "#E#{k} = #{v[0..400]}" }.join("\n\n")
        synth_prompt = Prompts.get(:rewoo, :synthesize, goal: goal, plan: plan_text.to_s, evidence: evidence_text)

        final = LLM.ask(synth_prompt, tier: :fast)
        return final unless final.ok?

        Result.ok(
          answer: final.value[:content],
          steps: @step,
          pattern: :rewoo,
          evidence: evidence,
          history: @history,
        )
      end
    end
  end
end
