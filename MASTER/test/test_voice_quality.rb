# frozen_string_literal: true

require_relative "test_helper"
require_relative "../tools/voice_quality"

class TestVoiceQualityHarness < Minitest::Test
  def test_probe_set_is_stable
    assert_equal 6, Master::Voice::QualityHarness::PROBES.length
    assert Master::Voice::QualityHarness::PROBES.all? { |text| text.split.length >= 7 }
  end

  def test_quality_limits_reject_clipping
    refute Master::Voice::QualityHarness.quality_ok?(
      ok: true, duration_s: 1.0, sample_rate: 24_000, clipping: true
    )
    assert Master::Voice::QualityHarness.quality_ok?(
      ok: true, duration_s: 1.0, sample_rate: 24_000, clipping: false
    )
  end
end
