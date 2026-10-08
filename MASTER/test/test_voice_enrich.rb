# frozen_string_literal: true

require_relative "test_helper"
require_relative "../lib/voice/enrich"

class TestVoiceEnrich < Minitest::Test
  def test_disabled_is_identity
    emotion = Master::Voice::Emotion.analyze("That is funny. It finally works.")
    assert_equal "That is funny. It finally works.", Master::Voice::Enrich.apply("That is funny. It finally works.", emotion)
  end

  def test_enabled_is_deterministic_and_capped
    text = "That is honestly wild. We finally fixed it. This is beautiful."
    emotion = Master::Voice::Emotion.analyze(text)
    first = Master::Voice::Enrich.apply(text, emotion, tags: true)
    second = Master::Voice::Enrich.apply(text, emotion, tags: true)

    assert_equal first, second
    assert_operator first.scan(/\[[a-z ]+\]/).length, :<=, 1
  end
end
