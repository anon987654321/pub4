# frozen_string_literal: true

require_relative "test_helper"
require_relative "../lib/voice/benchmark"

class TestVoiceBenchmark < Minitest::Test
  def test_torture_suite_has_varied_delivery_intents
    prompts = Master::Voice::Benchmark.torture_prompts.join(" ")

    assert_operator prompts.length, :>, 500
    assert_match(/?/, prompts)
    assert_match(/careful/i, prompts)
    assert_match(/unexpectedly/i, prompts)
    assert_match(/final point/i, prompts)
  end

  def test_speech_rate
    assert_in_delta 150.0, Master::Voice::Benchmark.speech_rate(25, 10), 0.001
    assert_equal 0.0, Master::Voice::Benchmark.speech_rate(0, 10)
  end

  def test_score_rejects_clipping_and_extreme_rate
    metrics = {
      duration_s: 10,
      clipped: true,
      dynamic_range_db: 2,
      silence: { count: 2, mean_ms: 900 },
      speech_rate_wpm: 300
    }

    result = Master::Voice::Benchmark.score(metrics, text: "one two three")
    refute result[:checks][:not_clipped]
    refute result[:checks][:dynamic_range]
    refute result[:checks][:rhythm]
    refute result[:checks][:speech_rate]
  end

  def test_score_accepts_reasonable_audio
    metrics = {
      duration_s: 8,
      clipped: false,
      dynamic_range_db: 12,
      silence: { count: 2, mean_ms: 180 },
      speech_rate_wpm: 155
    }

    result = Master::Voice::Benchmark.score(metrics, text: "one two three")
    assert_equal 100.0, result[:score]
  end
end
