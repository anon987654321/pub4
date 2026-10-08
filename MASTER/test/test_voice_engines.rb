# frozen_string_literal: true

require_relative "test_helper"
require_relative "../lib/voice/engines"

class TestVoiceEngines < Minitest::Test
  Engines = Master::Voice::Engines

  def test_rate_factor_is_bounded
    assert_in_delta 1.10, Engines.rate_factor("+10%"), 0.0001
    assert_in_delta 0.90, Engines.rate_factor("-10%"), 0.0001
    assert_in_delta 0.80, Engines.rate_factor("-40%"), 0.0001
    assert_in_delta 1.20, Engines.rate_factor("+40%"), 0.0001
  end

  def test_pitch_ratio_uses_the_shared_voice_reference
    Master::Voice::Policy.stub(:prosody, { "pitch_reference_hz" => 180 }) do
      assert_in_delta 1.10, Engines.pitch_ratio("+18Hz"), 0.0001
      assert_in_delta 0.90, Engines.pitch_ratio("-18Hz"), 0.0001
      assert_equal 1.0, Engines.pitch_ratio("+0Hz")
    end
  end

  def test_realize_audio_prosody_leaves_neutral_audio_untouched
    path = "/tmp/master_voice_neutral.mp3"
    File.write(path, "audio")

    assert_equal path, Engines.realize_audio_prosody(path, rate: "+0%", pitch: "+0Hz")
  ensure
    File.delete(path) if File.exist?(path)
  end

  def test_melodic_engine_keeps_edge_pitch_semantics
    plan = [{ text: "One.", rate: "+2%", pitch: "+6Hz", pause_ms: 0 }]
    observed = {}

    Engines.stub(:copy_if_synthesized, ->(_text, _path, voice, rate, pitch) {
      observed[:voice] = voice
      observed[:rate] = rate
      observed[:pitch] = pitch
      true
    }) do
      Engines.stub(:copy_single_part, ->(_parts, _out_path) { true }) do
        Engines.synthesize_phrase_parts(plan, "/tmp", :jenny, "-5%", "+0Hz")
      end
    end

    assert_equal :jenny, observed[:voice]
    assert_equal "+2%", observed[:rate]
    assert_equal "+6Hz", observed[:pitch]
  end
end
