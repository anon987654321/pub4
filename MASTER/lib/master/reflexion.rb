# frozen_string_literal: true

module Master
  # Critique-before-revision retry; lifts pass rate ~45%→90% (arxiv:2511.03153).
  module Reflexion
    MAX_REFLECTIONS = 3

    module_function

    def run(agent:, task:, fast_model: nil, max: MAX_REFLECTIONS)
      last_result = nil
      last_critique = nil

      (max + 1).times do |i|
        prompt = i.zero? ? task : build_revision_prompt(task, last_result, last_critique)
        last_result = yield(prompt, i)
        return last_result if last_result.respond_to?(:ok?) && last_result.ok?

        break if i >= max
        last_critique = critique(agent:, task:, result: last_result, fast_model:)
      end

      last_result
    end

    def critique(agent:, task:, result:, fast_model: nil)
      prompt = <<~PROMPT
        Task: #{task.to_s[0, 400]}
        Attempt output: #{result.to_s[0, 400]}
        What specifically went wrong? Name the constraint violated. What must change in the next attempt? One paragraph, no preamble.
      PROMPT
      resp = fast_model ? agent.ask_once_with_model(prompt, model: fast_model) : agent.ask(prompt)
      resp.respond_to?(:value!) ? resp.value! : resp.to_s
    rescue StandardError
      "previous attempt failed — try a different approach"
    end

    def build_revision_prompt(task, previous_result, critique)
      <<~PROMPT
        #{task}

        Previous attempt failed.
        Critique: #{critique}
        Previous output: #{previous_result.to_s[0, 200]}

        Revise based on the critique. Return only the corrected result.
      PROMPT
    end
  end
end
