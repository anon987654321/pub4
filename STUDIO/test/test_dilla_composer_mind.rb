# frozen_string_literal: true

require "minitest/autorun"
require_relative "../dilla/lib/composer_mind"

class TestDillaComposerMind < Minitest::Test
  def test_same_seed_and_history_is_deterministic
    a = DillaComposerMind.new(rng: Random.new(77))
    b = DillaComposerMind.new(rng: Random.new(77))
    2.times do
      a.observe_harmony("Dm9", [2, 5, 9, 0])
      b.observe_harmony("Dm9", [2, 5, 9, 0])
    end
    args = {
      candidates: [50, 52, 53, 55, 57, 59],
      previous: 53,
      chord_pcs: [2, 5, 9, 0],
      scale_pcs: [2, 4, 5, 7, 9, 10, 0],
      reach: 5,
    }
    assert_equal a.choose_note(**args), b.choose_note(**args)
  end

  def test_harmony_memory_rewards_a_new_chord_tone
    mind = DillaComposerMind.new(rng: Random.new(1))
    mind.observe_harmony("Dm9", [2, 5, 9, 0])
    mind.observe_harmony("Abmaj9", [8, 0, 3, 7])
    chosen = 48
    score = mind.choose_note(
      candidates: [chosen, 51],
      previous: 50,
      chord_pcs: [8, 0, 3, 7],
      scale_pcs: [8, 10, 0, 1, 3, 5, 7],
      reach: 5
    )
    assert_includes [48, 51], score
  end

  def test_critic_exposes_repetition_and_leaps
    mind = DillaComposerMind.new(rng: Random.new(9))
    [60, 67, 60, 67, 60].each { |note| mind.accept_note(note) }
    report = mind.critique
    assert_operator report.fetch(:notes), :>=, 5
    assert_operator report.fetch(:leap_rate), :>, 0.4
    assert report.fetch(:score).between?(0.0, 1.0)
  end
end
