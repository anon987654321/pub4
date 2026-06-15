# frozen_string_literal: true

module Master
  module Judge
    # GEPA-style reflective prompt evolution: mutate a prompt using natural-language reflections
    # (e.g. from the ReflexionLedger), score each candidate, and keep a Pareto frontier of the
    # best. Pure-Ruby orchestration — the single LLM call lives inside the injected mutator, so
    # this class is deterministic and testable. Refs: GEPA (arXiv:2507.19457).
    class PromptEvolver
      Candidate = Struct.new(:prompt, :score, keyword_init: true)

      def initialize(scorer:, mutator:, frontier_size: 5)
        @scorer = scorer       # callable: prompt -> 0.0..1.0
        @mutator = mutator     # callable: (prompt, reflections) -> new prompt string
        @frontier_size = frontier_size
      end

      # Reflectively evolve `seed_prompt` over `rounds`; returns the best Candidate found.
      def evolve(seed_prompt, reflections, rounds: 3)
        frontier = [score(seed_prompt)]
        [rounds, 0].max.times do
          parent = frontier.max_by(&:score)
          child = score(@mutator.call(parent.prompt, reflections))
          frontier = prune(frontier + [child])
        end
        frontier.max_by(&:score)
      end

      private

      def score(prompt)
        Candidate.new(prompt: prompt, score: @scorer.call(prompt).to_f)
      end

      def prune(candidates)
        candidates.uniq(&:prompt).sort_by { |candidate| -candidate.score }.first(@frontier_size)
      end
    end
  end
end
