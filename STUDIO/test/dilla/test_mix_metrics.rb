# frozen_string_literal: true

require_relative "helper"

# The measurement side. Every "the low end is 3 dB hot" claim this engine has
# ever made came out of parse_volumedetect, and it reads ffmpeg's log by
# regex -- ffmpeg emits one Parsed_volumedetect_N block per filter in the graph
# and does not emit them in index order, so an implementation that appended as
# it matched attributed the air band's reading to the sub band.
class TestMixMetrics < Minitest::Test
  LOG = <<~FFMPEG
    [Parsed_volumedetect_1 @ 0x600001] n_samples: 1000
    [Parsed_volumedetect_1 @ 0x600001] mean_volume: -22.5 dB
    [Parsed_volumedetect_1 @ 0x600001] max_volume: -6.0 dB
    [Parsed_volumedetect_0 @ 0x600000] n_samples: 1000
    [Parsed_volumedetect_0 @ 0x600000] mean_volume: -30.1 dB
    [Parsed_volumedetect_0 @ 0x600000] max_volume: -11.2 dB
  FFMPEG

  def test_readings_come_back_in_filter_order_not_log_order
    readings = send(:parse_volumedetect, LOG)

    assert_equal 2, readings.size
    assert_in_delta(-30.1, readings[0][:mean], 1e-9, "filter 0's reading is not first")
    assert_in_delta(-22.5, readings[1][:mean], 1e-9)
  end

  def test_both_readings_per_filter_are_kept
    readings = send(:parse_volumedetect, LOG)

    assert_in_delta(-11.2, readings[0][:max], 1e-9)
    assert_in_delta(-6.0, readings[1][:max], 1e-9)
  end

  def test_double_digit_filter_indexes_sort_numerically
    log = (0..11).map do |i|
      "[Parsed_volumedetect_#{i} @ 0x0] mean_volume: -#{20 + i}.0 dB\n"
    end.join
    means = send(:parse_volumedetect, log).map { |r| r[:mean] }

    assert_equal means.sort.reverse, means, "index 10 sorted before index 2"
  end

  def test_a_silent_or_failed_pass_yields_nothing_rather_than_a_zero
    assert_empty send(:parse_volumedetect, "")
    assert_empty send(:parse_volumedetect, "ffmpeg: no such file or directory")
  end

  def test_a_filter_that_reported_only_a_mean_is_still_returned
    readings = send(:parse_volumedetect, "[Parsed_volumedetect_0 @ 0x0] mean_volume: -14.0 dB")

    assert_equal 1, readings.size
    assert_in_delta(-14.0, readings[0][:mean], 1e-9)
    assert_nil readings[0][:max]
  end

  def test_positive_readings_parse_as_readily_as_negative_ones
    readings = send(:parse_volumedetect, "[Parsed_volumedetect_0 @ 0x0] max_volume: 0.0 dB")
    assert_in_delta 0.0, readings[0][:max], 1e-9
  end

  # The bands are what the readings are attributed to. An inverted or
  # zero-width band measures nothing and reports a number anyway.
  def test_every_metric_band_is_a_real_interval_inside_the_audible_range
    MIX_METRIC_BANDS.each do |name, (lo, hi)|
      assert_operator lo, :<, hi, "#{name} is inverted"
      assert_operator lo, :>=, 20, "#{name} starts below hearing"
      assert_operator hi, :<=, 22_050, "#{name} runs past Nyquist at 44.1k"
    end
  end

  def test_the_metric_bands_tile_the_spectrum_without_a_gap
    edges = MIX_METRIC_BANDS.values.sort_by(&:first)
    edges.each_cons(2) do |(_, hi), (lo, _)|
      assert_equal hi, lo, "a gap between #{hi} and #{lo} Hz is measured by nothing"
    end
  end

  def test_spectrum_bands_are_intervals_too
    RENDER_SPECTRUM_BANDS.each do |name, (lo, hi)|
      assert_operator lo, :<, hi, "#{name} is inverted"
    end
  end

  # RENDER_SPECTRUM_BANDS is not one tiling, it is two readings of the same
  # range at different crossovers -- a coarse three-way split and a finer
  # four-way one. That is why body/mid and high/air overlap. Asserting the two
  # tilings rather than the overlap set is what catches an edge moved in one
  # and not the other, which would make the two readings describe different
  # spectra while still looking like a table of six intervals.
  COARSE = %i[low mid high].freeze
  FINE = %i[low body presence air].freeze

  def assert_tiles(names)
    bands = names.map { |name| RENDER_SPECTRUM_BANDS.fetch(name) }
    bands.each_cons(2) do |(_, hi), (lo, _)|
      assert_equal hi, lo, "#{names.inspect} leaves a gap or an overlap at #{hi}/#{lo} Hz"
    end
    bands
  end

  def test_the_spectrum_is_read_as_two_complete_tilings_of_the_same_range
    coarse = assert_tiles(COARSE)
    fine = assert_tiles(FINE)

    assert_equal coarse.first.first, fine.first.first, "the two readings do not start together"
    assert_equal coarse.last.last, fine.last.last, "the two readings do not end together"
  end

  def test_the_two_readings_between_them_name_every_band
    assert_equal RENDER_SPECTRUM_BANDS.keys.sort, (COARSE | FINE).sort,
                 "a band belongs to neither reading, so nothing says what it is a reading of"
  end

  def test_the_measurement_window_is_long_enough_to_be_a_mix_and_short_enough_to_finish
    assert_operator MIX_METRIC_WINDOW_SEC, :>=, 30
    assert_operator MIX_METRIC_WINDOW_SEC, :<=, 600
  end
end
