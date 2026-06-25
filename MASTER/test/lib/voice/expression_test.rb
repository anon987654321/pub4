# frozen_string_literal: true

require_relative "../../test_helper"

class TestExpression < Minitest::Test
  def test_blendshapes_for_returns_normalized_fields
    shapes = Master::Voice::Expression.blendshapes_for(:dramatic)
    assert_includes shapes.keys, :jaw
    assert_includes shapes.keys, :smile
    assert_includes shapes.keys, :brow
    assert_includes shapes.keys, :lid_open
    shapes.each_value { |v| assert v.between?(0.0, 1.0) }
    assert shapes[:jaw] > Master::Voice::Expression.blendshapes_for(:whispered)[:jaw]
  end

  def test_for_tts_style_includes_blendshapes_and_decay_rate
    expr = Master::Voice::Expression.for_tts_style(:dramatic)
    assert expr[:blendshapes].is_a?(Hash)
    assert expr[:decay_rate].is_a?(Float)
    assert expr[:decay_rate] < Master::Voice::Expression.for_tts_style(:whispered)[:decay_rate]
  end

  def test_for_pre_speech_raises_arousal_and_attention
    pre = Master::Voice::Expression.for_pre_speech(style: :energetic, text: "hello world")
    assert pre[:arousal] > 0.7
    assert pre[:eye_attention] > 0.3
    assert pre[:breath_boost] > 0.0
  end

  def test_for_post_speech_dramatic_lingers_whispered_drops_fast
    dramatic = Master::Voice::Expression.for_post_speech(style: :dramatic)
    whispered = Master::Voice::Expression.for_post_speech(style: :whispered)
    assert dramatic[:linger_ms] > whispered[:linger_ms]
    assert whispered[:decay_rate] > dramatic[:decay_rate]
  end

  def test_viseme_hints_from_vowels_and_consonants
    hints = Master::Voice::Expression.viseme_hints("hello mom")
    assert hints.length >= 2
    assert_equal "E", hints[0][:shape]
    assert hints[0][:amp].between?(0.0, 1.0)
    assert hints[0][:ms].positive?
    assert hints.any? { |h| h[:shape] == "M" }
  end

  def test_fuse_confidence_merges_weighted_sources
    fused = Master::Voice::Expression.fuse_confidence(
      verdict: 0.9,
      retrieval: { score: 0.8 },
      council: 0.7
    )
    assert fused.between?(0.75, 0.85)
    assert_in_delta 0.75, Master::Voice::Expression.fuse_confidence({}), 0.001
  end

  def test_warm_erratic_pick_for_voice_keeps_voice
    pick = Master::Voice::Speech::VOICES.keys.sample
    result = Master::Voice::WarmErratic.pick_for_voice(pick, "Great, all done!")
    assert_equal pick, result[:voice]
    assert result[:rate].match?(/%/)
    assert result[:pitch].match?(/Hz/)
  end
end