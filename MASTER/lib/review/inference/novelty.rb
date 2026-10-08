# frozen_string_literal: true

require "digest"

module Master
  module Review
    module Inference
      module Novelty
        PERSPECTIVES = %i[direct expert observer].freeze
        DEBATE_ROLES = {
          logician: "Prioritise correctness, explicit assumptions and contradictions.",
          engineer: "Prioritise feasibility, failure modes, maintainability and cost.",
          contrarian: "Assume the obvious approach is wrong and hunt for a materially different mechanism."
        }.freeze

        module_function

        def denial(agent:, prompt:, constraints:, rounds:, temperature:)
          answers = []
          current = prompt.to_s

          rounds.times do |index|
            answer = agent.ask_once(current, temperature:)
            answers << answer
            constraint = Array(constraints)[index % Array(constraints).length]
            break unless constraint

            current = [
              prompt,
              "Previous candidate:",
              answer,
              "Deny that approach now. Produce a materially different solution.",
              "Forbidden approach: #{constraint}"
            ].join("

")
          end

          Master::Result.ok(strategy: :denial, rounds: answers.size, answers:)
        rescue StandardError => e
          Master::Result.err("inference: denial #{e.class}: #{e.message}", category: :handler_exception)
        end

        def strange_world(agent:, problem:, seeds:, temperature:)
          choices = Array(seeds).map(&:to_s).reject(&:empty?)
          return Master::Result.err("inference: strange world has no seeds") if choices.empty?

          index = Digest::SHA256.hexdigest(problem.to_s)[0, 8].to_i(16) % choices.length
          seed = choices[index]

          world = agent.ask_once(
            "You are a world builder. You see only the seed word below. Build a coherent alternative world with 3-5 precise rules of physics, causality, information or incentives. "             "Do not ask what pro...[truncated]