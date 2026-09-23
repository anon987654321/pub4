# frozen_string_literal: true

require_relative "test_helper"
require "master"

# frozen_string_literal: true
class TestMusicRhythm < Minitest::Test
  def test_grid_counts_steps
    grid = Master::Music::Rhythm.grid(bars: 1)
    assert_equal 16, grid.length
  end

  def test_dilla_time_shifts_odd_steps
    straight = Master::Music::Rhythm.grid(bars: 1, dilla: false)
    dilla = Master::Music::Rhythm.grid(bars: 1, dilla: true)
    assert dilla[1][:at] > straight[1][:at]
  end
end

# frozen_string_literal: true
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

# frozen_string_literal: true
class TestMusicSynth < Minitest::Test
  def test_writes_valid_wav_for_each_shape
    Dir.mktmpdir do |dir|
      Master::Music::Synth::SHAPES.each do |shape|
        path = File.join(dir, "#{shape}.wav")
        Master::Music::Synth.render(shape:, seconds: 0.02, destination: path)
        assert File.file?(path)
        assert_operator File.size(path), :>, 44
      end
    end
  end

  def test_unknown_shape_is_rejected
    assert_raises(ArgumentError) do
      Master::Music::Synth.render(shape: :purple, destination: "/tmp/never.wav")
    end
  end
end

