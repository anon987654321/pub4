# frozen_string_literal: true

require_relative "test_helper"
require_relative "../lib/voice/emotion"

class TestVoiceEmotion < Minitest::Test
  def test_analysis_is_deterministic
    first = Master::Voice::Emotion.analyze("Actually, this is beautiful. We finally fixed it.")
    second = Master::Voice::Emotion.analyze("Actually, this is beautiful. We finally fixed it.")

    assert_equal first, second
  end

  def test_structural_signals_are_exposed
    result = Master::Voice::Emotion.analyze("Wow! But maybe this is the part that matters?")
    assert_operator result[:structural][:question], :>, 0
    assert_operator result[:structural][:exclamation], :>, 0
    assert_operator result[:scores][:tension], :>, 0
    assert result[:blend].is_a?(Hash)
  end

  def test_continuous_scores_are_bounded
    result = Master::Voice::Emotion.analyze("done fixed beautiful wow critical maybe")
    result[:scores].each_value { |value| assert value.between?(0.0, 1.0) }
    %i[exaggeration cfg_weight warmth].each do |key|
      assert result[key].between?(0.0, 1.0)
    end
  end
end
