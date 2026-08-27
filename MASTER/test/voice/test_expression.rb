# frozen_string_literal: true

require_relative "../test_helper"

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

  def test_viseme_plan_accumulates_timing
    plan = Master::Voice::Expression.viseme_plan("hi", style: :energetic)
    assert plan.length >= 1
    assert_equal 0, plan[0][:t]
    assert plan[0][:ms] >= 28
    assert plan.last[:t] >= 0
  end

  def test_viseme_stream_includes_duration
    stream = Master::Voice::Expression.viseme_stream("open", style: :calm)
    assert stream[:viseme_plan].is_a?(Array)
    assert stream[:duration_ms].positive?
    assert_equal "expression_phoneme_heuristic", stream[:source]
  end

  def test_idle_signature_for_voice
    sig = Master::Voice::Expression.idle_signature_for(:osman)
    assert sig[:breath] > Master::Voice::Expression.idle_signature_for(:wayne)[:breath]
    assert sig[:blink_ms].positive?
  end

  def test_council_spirit_radius_scales_with_risk
    low = Master::Voice::Expression.council_spirit_radius(risk: :low, reversibility: :high)
    high = Master::Voice::Expression.council_spirit_radius(risk: :critical, reversibility: :low, persona_count: 6)
    assert high > low
  end

  def test_chain_styles_layers_whispered_and_ethereal
    chained = Master::Voice::Expression.chain_styles(:dramatic, :whispered)
    assert_equal %i[dramatic whispered], chained[:chained]
    assert chained[:breath_boost].is_a?(Numeric)
    assert chained[:blendshapes].is_a?(Hash)
  end

  def test_fuse_confidence_merges_weighted_sources
    fused = Master::Voice::Expression.fuse_confidence(
      verdict: 0.9,
      retrieval: { score: 0.8 },
      council: 0.7,
    )
    assert fused.between?(0.75, 0.85)
    assert_in_delta 0.75, Master::Voice::Expression.fuse_confidence({}), 0.001
  end

  def test_for_vertical_returns_bias_hash
    bias = Master::Voice::Expression.for_vertical(:dating)
    assert bias[:valence].positive?
    assert Master::Voice::Expression.for_vertical(:unknown).empty?
  end

  def test_mood_arc_from_history
    arc = Master::Voice::Expression.mood_arc(history: [
      { entropy: 0.8, valence: -0.2, arousal: 0.7 },
      { entropy: 0.6, valence: 0.1, arousal: 0.5 },
    ])
    assert arc[:entropy] > 0.5
    assert arc[:decay_rate] < 0.68
  end

  def test_for_council_persona_includes_lane
    expr = Master::Voice::Expression.for_council_persona("Skeptic")
    assert_equal :right, expr[:viseme_lane]
    assert expr[:arousal] > Master::Voice::Expression.for_council_persona("Mentor")[:arousal]
  end

  def test_warm_erratic_pick_for_voice_keeps_voice
    voice = Master::Voice::Policy.single_voice_key
    result = Master::Voice::WarmErratic.pick_for_voice(voice, "Great, all done!")
    assert_equal voice, result[:voice]
    assert result[:rate].match?(/%/)
    assert result[:pitch].match?(/Hz/)
  end
end
