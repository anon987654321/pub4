# frozen_string_literal: true

require_relative "test_helper"

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
