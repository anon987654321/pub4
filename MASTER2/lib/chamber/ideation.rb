# frozen_string_literal: true

module Chamber
  class Ideation
    def initialize(generator:, scorer: nil, logger: nil)
      @generator = generator
      @scorer = scorer
      @logger = logger
    end

    def ideate(prompt:, idea_count: 5, context: nil, constraints: [], seed_ideas: [])
      return [] unless prompt.to_s.strip.length.positive?
      return [] unless idea_count.to_i.positive?

      generated_ideas = generate_ideas(
        prompt: prompt,
        idea_count: idea_count,
        context: context,
        constraints: constraints,
        seed_ideas: seed_ideas
      )

      synthesize_ideas(
        raw_ideas: generated_ideas,
        prompt: prompt,
        idea_count: idea_count,
        constraints: constraints
      )
    end

    def synthesize_ideas(raw_ideas:, prompt:, idea_count:, constraints: [])
      return [] unless raw_ideas.is_a?(Array)
      return [] if raw_ideas.empty?

      candidate_ideas = normalize_ideas(raw_ideas)
      candidate_ideas = apply_constraints(candidate_ideas, constraints: constraints)
      return [] if candidate_ideas.empty?

      ranked_ideas = rank_ideas(candidate_ideas, prompt: prompt)
      ranked_ideas.first(idea_count)
    end

    private

    attr_reader :generator, :scorer, :logger

    def generate_ideas(prompt:, idea_count:, context:, constraints:, seed_ideas:)
      generator.generate(
        prompt: prompt,
        count: idea_count,
        context: context,
        constraints: constraints,
        seeds: seed_ideas
      )
    rescue StandardError => e
      logger&.warn("Ideation generator failed: #{e.class}: #{e.message}")
      []
    end

    def normalize_ideas(raw_ideas)
      raw_ideas
        .compact
        .map { |idea| idea.is_a?(Hash) ? idea[:text] || idea["text"] : idea }
        .map { |text| text.to_s.strip }
        .reject(&:empty?)
        .uniq
    end

    def apply_constraints(candidate_ideas, constraints:)
      return candidate_ideas if constraints.nil? || constraints.empty?

      candidate_ideas.select do |idea_text|
        constraints.all? { |constraint| constraint_satisfied?(idea_text, constraint) }
      end
    end

    def constraint_satisfied?(idea_text, constraint)
      case constraint
      when Regexp
        idea_text.match?(constraint)
      when Proc
        constraint.call(idea_text)
      when String
        idea_text.include?(constraint)
      else
        true
      end
    end

    def rank_ideas(candidate_ideas, prompt:)
      return candidate_ideas unless scorer

      candidate_ideas
        .map { |idea_text| [idea_text, scorer.score(prompt: prompt, idea: idea_text)] }
        .sort_by { |(_, score)| -score.to_f }
        .map(&:first)
    rescue StandardError => e
      logger&.warn("Ideation scoring failed: #{e.class}: #{e.message}")
      candidate_ideas
    end
  end
end