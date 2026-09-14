# frozen_string_literal: true

require_relative "studio_helper"
require_relative "../dilla/lib/sampling"

# Arithmetic in the support modules that render nothing, so a suite without
# audio or demucs can still hold it.
class TestDillaSupportModules < Minitest::Test
  # A rap vocal is fitted by time-stretch, never by varispeed: atempo keeps the
  # pitch, and nothing in the chain may move it.
  def test_the_vocal_fit_stretches_time_and_never_touches_pitch
    [0.3, 0.8, 1.0, 1.7, 4.5].each do |ratio|
      chain = Acapella.atempo_chain(ratio)
      stages = chain.split(",")

      assert stages.all? { |s| s.start_with?("atempo=") }, "#{chain} is not atempo alone"
      stages.each { |s| assert_includes 0.5..2.0, s.delete_prefix("atempo=").to_f, "#{s} is past one atempo's range" }
      assert_in_delta ratio, stages.map { |s| s.delete_prefix("atempo=").to_f }.reduce(:*), 1e-5
    end
  end

  def test_a_fast_beat_fits_the_vocal_at_half_time
    plan = Acapella.stretch_plan(from_bpm: 90, to_bpm: 90 * (Acapella::HALF_TIME_ABOVE + 0.5))

    assert plan[:half_time]
    assert_nil Acapella.stretch_plan(from_bpm: 0, to_bpm: 90)
  end

  def test_the_same_seed_picks_the_same_verse
    assert_equal Acapella.verse_start(200, "seed-a"), Acapella.verse_start(200, "seed-a")
    assert_equal 0.0, Acapella.verse_start(0, "seed-a")
  end

  def test_every_kit_role_is_a_one_shot_with_a_sane_band_and_length
    KitDig::ROLES.each do |file, spec|
      assert file.end_with?(".wav"), file
      low, high = spec[:band]
      assert_operator low, :<, high, "#{file} band"
      assert_operator spec[:min_len], :<, spec[:max_len], "#{file} length"
    end
  end

  def test_the_worth_weights_are_a_whole
    assert_in_delta 1.0, DillaSampleWorth::WEIGHTS.values.sum, 1e-9
    assert_empty DillaSampleWorth::HARMONY_TERMS - DillaSampleWorth::WEIGHTS.keys
  end
end
