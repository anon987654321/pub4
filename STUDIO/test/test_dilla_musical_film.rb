# frozen_string_literal: true

require "minitest/autorun"
require_relative "../dilla/lib/musical_film"

class TestDillaMusicalFilm < Minitest::Test
  def test_plan_contains_the_whole_stack
    plan = DillaMusicalFilm.plan(
      scene: "flylo_haze_01",
      index: 1,
      total: 5,
      seed: 42,
      tension: 0.3,
      energy: 0.6
    )
    %i[motif events midi_chain voices world_event dynamic architecture critique mutation next_scene].each do |key|
      assert plan.key?(key), "missing #{key}"
    end
    assert plan.fetch(:events).any?
    assert plan.fetch(:critique).fetch(:happened)
  end

  def test_plan_is_deterministic
    kwargs = { scene: "flylo_computer_face", index: 2, total: 5, seed: 17, tension: 0.55, energy: 0.7 }
    assert_equal DillaMusicalFilm.plan(**kwargs), DillaMusicalFilm.plan(**kwargs)
  end

  def test_critique_pushes_a_mutation_when_the_phrase_is_too_sparse
    result = DillaMusicalFilm.mutation_for({ score: 0.31, empty_space: 0.3, remained: 0.8 }, phase: :verse)
    assert_equal :fragment, result.fetch(:action)
  end
end
