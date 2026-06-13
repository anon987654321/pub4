# frozen_string_literal: true

module Master
  module Judge
    module Reflexion
      MAX_REFLECTIONS = 3
      TASK_TRUNCATE = 400
      HISTORY_TRUNCATE = 200
      BUDGET_SECONDS = 5 * 60

      module_function

      def run(agent:, task:, fast_model: nil, max: MAX_REFLECTIONS, budget_seconds: BUDGET_SECONDS)
        last_result = nil
        last_critique = nil
        deadline = Time.now + budget_seconds

        (max + 1).times do |i|
          break if Time.now >= deadline
          prompt = i.zero? ? task : build_revision_prompt(task, last_result, last_critique)
          last_result = yield(prompt, i)
          return last_result if last_result.is_a?(Master::Result) && last_result.ok?

          break if i >= max
          break if circuit_open?(agent)
          last_critique = critique(agent:, task:, result: last_result, fast_model:)
        end

        last_result
      end

      def circuit_open?(agent)
        breaker = agent.respond_to?(:circuit_breaker) ? agent.circuit_breaker : nil
        return false unless breaker.respond_to?(:open_models)
      rescue StandardError => e
        Master::Ground::Swallow.log(e, context: "Reflexion.circuit_open?")
        false
      end

      def critique(agent:, task:, result:, fast_model: nil)
        prompt = <<~PROMPT
        Task: #{task.to_s[0, TASK_TRUNCATE]}
        Attempt output: #{result.to_s[0, TASK_TRUNCATE]}
        What specifically went wrong? Name the constraint violated.
        What must change in the next attempt? One paragraph, no preamble.
      PROMPT
        resp = fast_model ? agent.ask_once(prompt, model: fast_model) : agent.ask(prompt)
        resp.respond_to?(:value!) ? resp.value! : resp.to_s
      rescue StandardError => e
        Master::Ground::Swallow.log(e, context: "Reflexion.critique")
        "previous attempt failed — try a different approach"
      end

      def build_revision_prompt(task, previous_result, critique)
        <<~PROMPT
        #{task}

        Previous attempt failed.
        Critique: #{critique}
        Previous output: #{previous_result.to_s[0, HISTORY_TRUNCATE]}

        Revise based on the critique. Return only the corrected result.
      PROMPT
      end
    end
  end
end
