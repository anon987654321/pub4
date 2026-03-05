# frozen_string_literal: true

module MASTER
  class Executor
    module Reflexion
      REFLECT_SCHEMA = {
        type: "object",
        additionalProperties: false,
        required: %w[success critique lessons],
        properties: {
          success:         { type: "boolean", description: "Did the attempt fully complete the task?" },
          critique:        { type: "string",  description: "What went wrong or could be improved" },
          lessons:         { type: "string",  description: "Concrete changes for the next attempt" },
          improved_answer: { type: "string",  description: "Better answer if the original was incomplete" },
        },
      }.freeze

      def execute_reflexion(goal, tier:)
        original_goal = goal.dup.freeze
        max_attempts = 3
        attempt = 0

        while attempt < max_attempts
          attempt += 1
          UI.dim("  attempt #{attempt}/#{max_attempts}")

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

        Result.err("Failed after #{max_attempts} attempts with reflection")
      end

      def execute_react_inner(goal, tier:)
        # Simplified ReAct without the outer Result wrapper.
        # Uses ask_json + STEP_SCHEMA (same as execute_react) to avoid regex parsing.
        start_time = MASTER::Utils.monotonic_now

        [5, @max_steps - @step].min.times do
          begin
            check_timeout!(start_time)
          rescue Result::Error => e
            return Result.err(e.message)
          end

          @step += 1
          msgs = build_context_messages(goal)

          result = LLM.ask_json(msgs.last[:content], schema: STEP_SCHEMA, messages: [msgs.first], tier: tier)
          return Result.err("LLM error at step #{@step}: #{result.error}") unless result.ok?

          parsed = parse_step(result.value[:content])
          record_history({ step: @step, thought: parsed[:thought], action: parsed[:action] })

          return Result.ok(answer: parsed[:answer], steps: @step) if parsed[:answer]

          observation = dispatch_action(parsed[:tool] || parsed[:action])
          @history.last[:observation] = observation
        end

        Result.err("No answer in 5 steps.")
      end

      def reflect_on_result(goal, result, tier:)
        history_text = @history.map do |h|
          "#{h[:thought]} -> #{h[:action]} -> #{h[:observation]&.[](0..200)}"
        end.join("\n")

        prompt = <<~REFLECT
          Task: #{goal}

          Execution trace:
          #{history_text}

          Result: #{result.ok? ? result.value[:answer] : result.error}

          Reflect: did this fully complete the task? What went wrong? What should change next attempt?
          If the answer was incomplete, provide an improved_answer.
        REFLECT

        llm_result = LLM.ask_json(prompt, schema: REFLECT_SCHEMA, tier: tier)
        return { success: false, critique: "Reflection LLM call failed", lessons: "" } unless llm_result.ok?

        r = llm_result.value[:content]
        {
          success:         r[:success] || r["success"] || false,
          critique:        r[:critique] || r["critique"] || "",
          lessons:         r[:lessons]  || r["lessons"]  || "",
          improved_answer: r[:improved_answer] || r["improved_answer"],
        }
      end
    end
  end
end
