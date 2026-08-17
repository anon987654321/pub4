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

  # Segmentation and rests are rhythm; the pentatonic pitch targets are a style.
  # They were one plan behind one threshold, so ordinary speech got neither.
  def test_plain_phrase_plan_keeps_rests_and_drops_the_contour
    text = "I found it. But there is a problem."
    emotion = Master::Voice::Emotion.analyze(text)
    plan = Master::Voice::Melody.plan(text, emotion, melodic: false)

    assert_operator plan[:phrases].length, :>=, 2
    refute plan[:melodic]
    assert_nil plan[:phrases][0][:pitch], "the contour is the melodic mode, not the rhythm"
    assert_nil plan[:phrases][0][:rate]
    assert_operator plan[:phrases][1][:pause_ms], :>, 0, "a rest between phrases is the point"
  end

  def test_first_phrase_never_carries_a_leading_rest
    emotion = Master::Voice::Emotion.analyze("One. Two. Three.")
    plan = Master::Voice::Melody.plan("One. Two. Three.", emotion, melodic: false)

    assert_equal 0, plan[:phrases][0][:pause_ms]
  end

  # Each phrase is its own Edge round trip, so segmentation is a fan-out
  # multiplier on a 1 vCPU box.
  def test_segmentation_is_bounded_so_fan_out_is_bounded
    text = (1..40).map { |i| "Sentence number #{i}." }.join(" ")

    assert_equal Master::Voice::Melody::MAX_PHRASES, Master::Voice::Melody.segment(text).length
  end

  def test_segmentation_keeps_every_word_when_it_merges_the_tail
    text = (1..40).map { |i| "Sentence number #{i}." }.join(" ")
    segmented = Master::Voice::Melody.segment(text).join(" ")

    assert_equal text.split.length, segmented.split.length
  end

  # melodic_threshold now gates only the contour. Phrase rendering is reached by
  # either, so ordinary text still renders phrase by phrase.
  def test_phrase_rendering_survives_below_the_lyrical_threshold
    cfg = Master::Voice::Transcendent.load_config.merge("phrase_rhythm_enabled" => true)
    flat = { scores: { lyrical: 0.0 } }

    refute Master::Voice::Transcendent.melodic_contour?(cfg, flat)
    assert Master::Voice::Transcendent.phrase_rendered?(cfg, flat)
    assert_includes Master::Voice::Transcendent.build_engine_chain(cfg, flat), "edge_melodic"
  end

  def test_phrase_rendering_is_switchable_back_off
    cfg = Master::Voice::Transcendent.load_config.merge("phrase_rhythm_enabled" => false)
    flat = { scores: { lyrical: 0.0 } }

    refute Master::Voice::Transcendent.phrase_rendered?(cfg, flat)
    refute_includes Master::Voice::Transcendent.build_engine_chain(cfg, flat), "edge_melodic"
  end

  def test_lyrical_text_still_reaches_the_contour_with_rhythm_off
    cfg = Master::Voice::Transcendent.load_config
             .merge("phrase_rhythm_enabled" => false, "emotion_enabled" => true, "melodic_enabled" => true)
    lyrical = { scores: { lyrical: 0.9 } }

    assert Master::Voice::Transcendent.melodic_contour?(cfg, lyrical)
    assert_includes Master::Voice::Transcendent.build_engine_chain(cfg, lyrical), "edge_melodic"
  end
end
