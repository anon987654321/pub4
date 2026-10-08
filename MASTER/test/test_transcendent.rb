<sub># frozen_string_literal: true

require_relative "test_helper"

class TestTranscendent < Minitest::Test
  def test_emotion_analyze_returns_profile
    e = Master::Voice::Emotion.analyze("Great, breakthrough done! lol wild")
    assert_includes %i[triumph humor wonder warm urgent comfort], e[:primary]
    assert e[:scores][:valence] > 0.5
    assert e[:blend].is_a?(Hash)
    assert e[:scores].key?(:tension)
  end

  def test_melody_plan_phrases
    emotion = Master::Voice::Emotion.analyze("Done! Queue ready. Sing la la.")
    plan = Master::Voice::Melody.plan("Done! Queue ready. Sing la la.", emotion)
    assert plan[:phrases].length >= 2
    assert plan[:phrases][0][:pitch].match?(/Hz\z/)
  end

  def test_melody_pitch_contour_stays_small_and_centered
    emotion = Master::Voice::Emotion.analyze("Done! Queue ready. Sing la la.")
    plan = Master::Voice::Melody.plan("Done! Queue ready. Sing la la.", emotion)

    pitches = plan[:phrases].map { |phrase| phrase[:pitch].delete("Hz").to_i }
    assert pitches.all? { |pitch| (-10..10).cover?(pitch) }
    assert_equal 0, pitches.first
    assert_includes pitches, -6
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

  def test_default_phrase_rendering_is_enabled_for_spoken_performance
    cfg = Master::Voice::Transcendent.load_config
    flat = { scores: { lyrical: 0.0 }, mode: :conversational }

    assert Master::Voice::Transcendent.phrase_rendered?(cfg, flat)
    assert_includes Master::Voice::Transcendent.build_engine_chain(cfg, flat), "edge_melodic"
  end

  def test_phrase_rendering_is_switchable_back_off
    cfg = Master::Voice::Transcendent.load_config.merge("phrase_rhythm_enabled" => false)
    flat = { scores: { lyrical: 0.0 }, mode: :conversational }

    refute Master::Voice::Transcendent.phrase_rendered?(cfg, flat)
    refute_includes Master::Voice::Transcendent.build_engine_chain(cfg, flat), "edge_melodic"
  end

  def test_lyrical_text_reaches_the_contour
    cfg = Master::Voice::Transcendent.load_config
             .merge("phrase_rhythm_enabled" => true, "emotion_enabled" => true, "melodic_enabled" => true)
    lyrical = { scores: { lyrical: 0.9 }, mode: :melodic }

    assert Master::Voice::Transcendent.melodic_contour?(cfg, lyrical)
    assert_includes Master::Voice::Transcendent.build_engine_chain(cfg, lyrical), "edge_melodic"
  end

  def test_melodic_performance_changes_timing_and_blends_pitch
    melody = {
      melodic: true,
      phrases: [
        { text: "One.", rate: "+2%", pitch: "+6Hz", pause_ms: 90 },
        { text: "Two.", rate: "+1%", pitch: "-6Hz", pause_ms: 140 },
      ],
    }
    performance = [
      { rate: "-2%", pitch: "+12Hz", pause_ms: 100, role: :opening, emphasis: :none },
      { rate: "+2%", pitch: "-12Hz", pause_ms: 180, role: :closing, emphasis: :none },
    ]

    Master::Voice::Performance.stub(:apply, performance) do
      rendered = Master::Voice::Transcendent.apply_spoken_performance(
        melody, "One. Two.", {}, :auto, base_rate: "-5%", base_pitch: "+0Hz"
      )
      assert_equal ["+6Hz", "-6Hz"], rendered[:phrases].map { |phrase| phrase[:pitch] }
      assert_equal ["+5%", "+8%"], rendered[:phrases].map { |phrase| phrase[:rate] }
    end
  end
  def test_voice_quality_probe_rejects_missing_audio
    result = Master::Voice::Quality.inspect("/tmp/master-no-such-tts-file.mp3")
    refute result[:ok]
    assert_equal :missing, result[:reason]
  end
end
</sub>