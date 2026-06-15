# frozen_string_literal: true

require_relative "test_helper"

# GEPA-style reflective prompt evolution: mutate from reflections, keep the best candidate.
class TestPromptEvolver < Minitest::Test
  def test_evolves_toward_higher_scoring_prompt
    # Scorer rewards longer prompts; mutator appends a reflection each round.
    scorer = ->(prompt) { prompt.length / 100.0 }
    mutator = ->(prompt, reflections) { "#{prompt} | #{reflections.first}" }

    evolver = Master::Judge::PromptEvolver.new(scorer: scorer, mutator: mutator)
    best = evolver.evolve("seed", ["avoid syntax errors"], rounds: 3)

    assert_operator best.score, :>, scorer.call("seed")
    assert_includes best.prompt, "avoid syntax errors"
  end

  def test_keeps_seed_when_mutations_do_not_help
    scorer = ->(prompt) { prompt == "seed" ? 1.0 : 0.0 }
    mutator = ->(_prompt, _reflections) { "worse" }

    best = Master::Judge::PromptEvolver.new(scorer: scorer, mutator: mutator).evolve("seed", [], rounds: 3)
    assert_equal "seed", best.prompt
  end
end
