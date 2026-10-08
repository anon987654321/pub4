# frozen_string_literal: true

require_relative "test_helper"
require_relative "../lib/voice/performance"

class TestVoicePerformanceTimeline < Minitest::Test
  def test_timeline_uses_one_audio_clock
    timeline = Master::Voice::Performance.timeline(
      "Ready. The key is simple.",
      style: :warm,
      rate: "-5%",
      pitch: "-12Hz",
      voice: :jenny,
    )

    assert_equal 1, timeline[:schema]
    assert_equal "audio", timeline[:clock]
    assert_equal true, timeline[:duration_normalization]
    assert_match(/\A[0-9a-f]{20}\z/, timeline[:performance_id])
    assert_operator timeline[:estimated_duration_ms], :>, 0
    assert_operator timeline[:events].length, :>, 0
    assert timeline[:events].each_cons(2).all? { |a, b| a[:at_ms] <= b[:at_ms] }
    assert timeline[:events].all? { |event| event[:at_ms] <= timeline[:estimated_duration_ms] }
  end

  def test_timeline_identity_includes_synthesis_parameters
    base = Master::Voice::Performance.timeline(
      "Ready.",
      style: :warm,
      rate: "-5%",
      pitch: "-12Hz",
      voice: :jenny,
    )
    changed = Master::Voice::Performance.timeline(
      "Ready.",
      style: :dramatic,
      rate: "+0%",
      pitch: "+0Hz",
      voice: :andrew,
    )

    refute_equal base[:performance_id], changed[:performance_id]
  end
end
