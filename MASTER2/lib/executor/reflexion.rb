# frozen_string_literal: true

module MASTER
  class Executor
    module Reflexion
      REFLEXION_MAX_ATTEMPTS  = 3
      INNER_REACT_MAX_STEPS   = 5
      def execute_reflexion(goal, tier:)
        original_goal = goal.dup.freeze
        attempt = 0

        while attempt < REFLEXION_MAX_ATTEMPTS
          attempt += 1
          UI.dim("  attempt #{attempt}/#{REFLEXION_MAX_ATTEMPTS}")

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
            UI.dim("  ok")
            return Result.ok(
              answer: result.ok? ? result.value[:answer] : reflection[:improved_answer],
              steps: @step,
              pattern: :reflexion,
              attempts: attempt,
              reflections: @reflections,
              history: @history,
            )
          end

          UI.dim("  #{reflection[:critique][0..60]}")

          @history = [] # Reset for fresh attempt
          @step = 0
        end

        Result.err("Failed after #{REFLEXION_MAX_ATTEMPTS} attempts with reflection")
      end

      def execute_react_inner(goal, tier:)
        # Simplified ReAct without the outer Result wrapper
        # Intentionally cap inner loop to respect overall step budget
        start_time = MASTER::Utils.monotonic_now

        [INNER_REACT_MAX_STEPS, @max_steps - @step].min.times do
          return err if (err = timeout_error_for(start_time))

          @step += 1
          msgs = build_context_messages(goal)

          result = LLM.ask(msgs.last[:content], messages: [msgs.first], tier: tier)
          return Result.err("LLM error.") unless result.ok?

          parsed = parse_response(result.value[:content].to_s)
          record_history({ step: @step, thought: parsed[:thought], action: parsed[:action] })

          if parsed[:action] =~ COMPLETION_PATTERN
            answer = parsed[:action].sub(COMPLETION_PATTERN, "")
            return Result.ok(answer: answer, steps: @step)
          end

          observation = dispatch_action(parsed[:action])
          @history.last[:observation] = observation
        end

        Result.err("No answer in #{INNER_REACT_MAX_STEPS} steps.")
      end

      def reflect_on_result(goal, result, tier:)
        history_text = @history.map do |h|
          "#{h[:thought]} -> #{h[:action]} -> #{h[:observation]&.[](0..200)}"
        end.join("\n")
        result_text  = result.ok? ? result.value[:answer] : result.error
        prompt = Prompts.get(:reflexion, :reflect, goal: goal, history: history_text, result: result_text)

        llm_result = LLM.ask(prompt, tier: tier)
        return { success: false, critique: "Reflection LLM call failed", lessons: "" } unless llm_result.ok?

        content = llm_result.value[:content]
        {
          success: content.match?(/SUCCESS:\s*yes/i),
          critique: content[/CRITIQUE:\s*(.+?)(?=LESSONS:|$)/mi, 1]&.strip || "",
          lessons: content[/LESSONS:\s*(.+?)(?=IMPROVED_ANSWER:|$)/mi, 1]&.strip || "",
          improved_answer: content[/IMPROVED_ANSWER:\s*(.+)/mi, 1]&.strip,
        }
      end
    end
  end
end
