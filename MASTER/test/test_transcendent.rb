# frozen_string_literal: true

require_relative "test_helper"

class TestTranscendent < Minitest::Test
  def test_emotion_analyze_returns_profile
    e = Master::Voice::Emotion.analyze("Great, breakthrough done! lol wild")
    assert_includes %i[triumph humor wonder warm urgent comfort], e[:primary]
    assert e[:scores][:valence] > 0.5
  end

  def test_melody_plan_phrases
    emotion = Master::Voice::Emotion.analyze("Done! Queue ready. Sing la la.")
    plan = Master::Voice::Melody.plan("Done! Queue ready. Sing la la.", emotion)
    assert plan[:phrases].length >= 2
    assert plan[:phrases][0][:pitch].match?(/Hz\z/)
  end

  def test_warm_erratic_pick
    pick = Master::Voice::WarmErratic.pick("Sorry, that failed unfortunately.")
    assert Master::Voice::Speech::VOICES.key?(pick[:voice])
    assert pick[:rate].match?(/%/)
  end

  def test_transcendent_synthesize_empty_returns_nil
    assert_nil Master::Voice::Transcendent.synthesize("")
  end

  def test_engine_chain_respects_availability
    cfg = Master::Voice::Transcendent.load_config
    assert cfg["engine_chain"].include?("edge")
  end
end