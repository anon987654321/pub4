# frozen_string_literal: true

module Master
  module Review
    module Inference
      module Optimizer
        Candidate = Data.define(:prompt, :scores, :aggregate)

        module_function

        # GEPA-shaped optimisation: rollout -> reflect -> mutate -> Pareto select.
        # It deliberately stays in-memory. Production prompts change only when
        # a human or a separately verified repository change promotes a winner.
        def gepa(agent:, prompt:, dataset:, metric:, generations:, population:, temperature:)
          population_size = [population.to_i, 1].max
          seeds = [Candidate.new(prompt: prompt.to_s, scores: [], aggregate: 0.0)]

          generations.to_i.times do
            seeded = seeds.map do |candidate|
              scores = score_candidate(agent, candidate.prompt, dataset, metric, temperature:)
              Candidate.new(prompt: candidate.prompt, scores:, aggregate: mean(scores))
            end
            reflections = seeded.map do |candidate|
              [candidate, reflect(agent, candidate.prompt, candidate.scores, temperature:)]
            end
            mutations = reflections.flat_map do |candidate, reflection|
              Array.new(population_size) { mutate(agent, candidate.prompt, reflection, temperature:) }
            end

            candidates = seeded + mutations.map do |candidate_prompt|
              scores = score_candidate(agent, candidate_prompt, dataset, metric, temperature:)
              Candidate.new(prompt: candidate_prompt.to_s.strip, scores:, aggregate: mean(scores))
            end
            seeds = pareto_frontier(candidates).sort_by { |candidate| [-candidate.aggregate, candidate.prompt] }
                       .first(population_size)
          end

          final = seeds.map do |candidate|
            next candidate if candidate.scores.any?
            scores = score_candidate(agent, candidate.prompt, dataset, metric, temperature:)
            Candidate.new(prompt: candidate.prompt, scores:, aggregate: mean(scores))
          end
          winner = final.max_by { |candidate| [candidate.aggregate, candidate.prompt] }
          Master::Result.ok(strategy: :gepa, winner:, frontier: pareto_frontier(final))
        rescue StandardError => e
          Master::Result.err("inference: GEPA #{e.class}: #{e.message}", category: :handler_exception)
        end

        def score_candidate(agent, prompt, dataset, metric, temperature:)
          Array(dataset).map do |example|
            output = agent.ask_once("#{prompt}\n\nInput:\n#{example[:input]}", temperature:)
            metric.call(example, output).to_f
          end
        end
        private_class_method :score_candidate

        def mean(scores)
          values = Array(scores)
          values.empty? ? 0.0 : values.sum.to_f / values.length
        end
        private_class_method :mean

        def reflect(agent, prompt, scores, temperature:)
          agent.ask_once(
            "Reflect on this prompt optimiser candidate. Identify the smallest textual changes likely to improve its scores without changing the task contract. Do not solve the task.\n\n"             "Prompt:\n#{prompt}\n\nScores:\n#{scores.inspect}",
            temperature:,
          )
        end
        private_class_method :reflect

        def mutate(agent, prompt, reflection, temperature:)
          agent.ask_once(
            "Mutate this prompt using the reflection. Keep the task contract intact. Return only the mutated prompt.\n\nCurrent:\n#{prompt}\n\nReflection:\n#{reflection}",
            temperature:,
          )
        end
        private_class_method :mutate

        def pareto_frontier(candidates)
          Array(candidates).select do |candidate|
            Array(candidates).none? do |other|
              other != candidate &&
                dominates?(other.scores, candidate.scores) &&
                other.scores != candidate.scores
            end
          end
        end
        private_class_method :pareto_frontier

        def dominates?(left, right)
          left.zip(right).all? { |a, b| a >= b } && left.zip(right).any? { |a, b| a > b }
        end
        private_class_method :dominates?
      end
    end
  end
end
