# frozen_string_literal: true

module MASTER
  class Executor
    module React
      def execute_react(goal, tier:)
        start_time = MASTER::Utils.monotonic_now

        while @step < @max_steps
          begin
            check_timeout!(start_time)
          rescue Result::Error => e
            return Result.err(e.message)
          end

          @step += 1

          msgs = build_context_messages(goal)

          result = LLM.ask(msgs.last[:content], messages: [msgs.first], tier: tier)
          unless result.ok?
            return Result.err("LLM error at step #{@step}: #{result.error}")
          end

          parsed = parse_response(result.value[:content])
          record_history({ step: @step, thought: parsed[:thought], action: parsed[:action] })

          # Show progress
          UI.dim("  #{@step}: #{parsed[:thought][0..80]}")
          UI.dim("  > #{parsed[:action][0..60]}")

          # Check for completion
          if parsed[:action] =~ COMPLETION_PATTERN
            answer = parsed[:action].sub(COMPLETION_PATTERN, "")
            return Result.ok(
              answer: answer,
              steps: @step,
              pattern: :react,
              history: @history
            )
          end

          # Execute tool and get observation
          observation = execute_tool(parsed[:action])
          @history.last[:observation] = observation

          UI.dim("  = #{observation[0..100]}")
        end

        Result.err("Max steps (#{@max_steps}) reached without completion")
      end
    end

    # --- Pre-Act pattern implementation ---
  end
end
