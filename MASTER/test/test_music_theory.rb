# frozen_string_literal: true

require_relative "test_helper"

class TestMusicTheory < Minitest::Test
  def test_minor_scale
    assert_equal %w[C D D# F G G# A#], Master::Music::Theory.scale(root: "C", name: :minor)
  end

  def test_minor7_chord
    assert_equal %w[C D# G A#], Master::Music::Theory.chord(root: "C", quality: :minor7)
  end

  def test_dilla_progression_has_four_chords
    chords = Master::Music::Theory.progression(root: "C", name: :dilla_love)
    assert_equal 4, chords.length
    assert chords.all? { |chord| chord.length == 4 }
  end
end
