# frozen_string_literal: true

module MASTER
  class Executor
    module Reflexion
      def execute_reflexion(goal, tier:)
        original_goal = goal.dup.freeze
        max_attempts = 3
        attempt = 0

        while attempt < max_attempts
          attempt += 1
          UI.dim("  🔄 Attempt #{attempt}/#{max_attempts}")

          # Build augmented goal from original + all lessons so far
          augmented_goal = if @reflections.any?
            lessons = @reflections.map { |r| r[:lessons] }.compact.reject(&:empty?)
            "#{original_goal}\n\nLESSONS FROM PREVIOUS ATTEMPTS:\n#{lessons.join("\n")}"
          else
            original_goal
          end

          # Execute using ReAct
          result = execute_react_inner(augmented_goal, tier: tier)

          # Reflect on the result
          reflection = reflect_on_result(original_goal, result, tier: :fast)
          @reflections << reflection

          if reflection[:success]
            UI.dim("  ✓ Reflection: Success")
            return Result.ok(
              answer: result.ok? ? result.value[:answer] : reflection[:improved_answer],
              steps: @step,
              pattern: :reflexion,
              attempts: attempt,
              reflections: @reflections,
              history: @history
            )
          end

          UI.dim("  ⚠ Reflection: #{reflection[:critique][0..60]}...")

          @history = [] # Reset for fresh attempt
          @step = 0
        end

        Result.err("Failed after #{max_attempts} attempts with reflection")
      end

      def execute_react_inner(goal, tier:)
        # Simplified ReAct without the outer Result wrapper
        # Intentionally cap inner loop to respect overall step budget
        start_time = MASTER::Utils.monotonic_now

        [5, @max_steps - @step].max.times do
          begin
            check_timeout!(start_time)
          rescue Result::Error => e
            return Result.err(e.message)
          end

          @step += 1
          context = build_context(goal)

          result = LLM.ask(context, tier: tier)
          return Result.err("LLM error") unless result.ok?

          parsed = parse_response(result.value[:content])
          record_history({ step: @step, thought: parsed[:thought], action: parsed[:action] })

          if parsed[:action] =~ COMPLETION_PATTERN
            answer = parsed[:action].sub(COMPLETION_PATTERN, "")
            return Result.ok(answer: answer, steps: @step)
          end

          observation = execute_tool(parsed[:action])
          @history.last[:observation] = observation
        end

        Result.err("No answer in 5 steps")
      end

      def reflect_on_result(goal, result, tier:)
        history_text = @history.map do |h|
          "#{h[:thought]} → #{h[:action]} → #{h[:observation]&.[](0..200)}"
        end.join("\n")

        prompt = <<~REFLECT
          Task: #{goal}

          Execution trace:
          #{history_text}

          Result: #{result.ok? ? result.value[:answer] : result.error}

          Reflect on this execution:
          1. Did it successfully complete the task? (yes/no)
          2. What went wrong or could be improved?
          3. What lessons should be applied to the next attempt?
          4. If the answer was incomplete, provide an improved answer.

          Respond in this format:
          SUCCESS: yes/no
          CRITIQUE: (what went wrong)
          LESSONS: (what to do differently)
          IMPROVED_ANSWER: (better answer if needed)
        REFLECT

        result = LLM.ask(prompt, tier: tier)
        return { success: true, critique: "", lessons: "" } unless result.ok?

        content = result.value[:content]
        {
          success: content.match?(/SUCCESS:\s*yes/i),
          critique: content[/CRITIQUE:\s*(.+?)(?=LESSONS:|$)/mi, 1]&.strip || "",
          lessons: content[/LESSONS:\s*(.+?)(?=IMPROVED_ANSWER:|$)/mi, 1]&.strip || "",
          improved_answer: content[/IMPROVED_ANSWER:\s*(.+)/mi, 1]&.strip
        }
      end
    end

    # ═══════════════════════════════════════════════════════════════════════════
    # Tools module - All tool execution and dispatch logic
    # ═══════════════════════════════════════════════════════════════════════════
  end
end
