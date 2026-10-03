# frozen_string_literal: true

require_relative "dilla_helper"
require_relative "../dilla/lib/livesets"

# The Röyksopp chord source rides inside the engine now: module Royksopp in
# dilla.rb, reached as the `royksopp_live` progression. These pin the verified
# Melody A.M. cells it keeps as harmonic data.
class TestDillaRoyksopp < Minitest::Test
  def test_remind_me_progression_is_the_documented_four_chord_cell
    assert_equal %w[Dm7 Am7 Ebmaj7 Bb], Royksopp::SOURCES.fetch(:remind_me).fetch(:chords)
  end

  def test_shes_so_progression_is_the_documented_four_chord_cell
    assert_equal %w[Dm7 Gm7 Ebmaj7 Abmaj7], Royksopp::SOURCES.fetch(:shes_so).fetch(:chords)
  end

  def test_so_easy_sections_keep_their_real_chord_cells
    assert_equal %w[Cm Bb Dm], Royksopp::SOURCES.fetch(:so_easy_c_minor).fetch(:chords)
    assert_equal %w[Am G Bm], Royksopp::SOURCES.fetch(:so_easy_a_minor).fetch(:chords)
    assert_equal %w[Em Bm D], Royksopp::SOURCES.fetch(:so_easy_e_minor).fetch(:chords)
  end

  def test_chord_parser_preserves_quality_and_root
    assert_equal({ symbol: "Dm7", root_pc: 2, tones: [5, 9, 0, 2] }, Royksopp.chord("Dm7"))
    assert_equal({ symbol: "Ebmaj7", root_pc: 3, tones: [7, 10, 2, 3] }, Royksopp.chord("Ebmaj7"))
    assert_equal({ symbol: "Bb", root_pc: 10, tones: [2, 5, 10, 2] }, Royksopp.chord("Bb"))
  end

  def test_style_routing_uses_the_shared_steerable_progression
    assert_equal %w[progression royksopp_live], LiveSynth::Say.style_args("röyksopp")
  end

  def test_royksopp_live_progression_uses_the_verified_suite
    score = LiveSynth::Progression.new("royksopp_live", rng: Random.new(1), loops: 1)
    chords = score.instance_variable_get(:@chords).map { |chord| chord["name"] }
    assert_equal Royksopp::SUITE, chords
    refute score.instance_variable_get(:@p).fetch("master").empty?
  end
end