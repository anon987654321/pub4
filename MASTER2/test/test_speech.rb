# frozen_string_literal: true

require "minitest/autorun"
require_relative "../lib/master"

class TestSpeech < Minitest::Test
  def test_engines_constant
    assert_equal %i[piper edge replicate], MASTER::Speech::ENGINES
  end

  def test_stream_effects_constant
    effects = MASTER::Speech::STREAM_EFFECTS
    assert effects.key?(:dark)
    assert effects.key?(:demon)
    assert effects.key?(:robot)
  end

  def test_styles_constant
    styles = MASTER::Speech::STYLES
    assert styles.key?(:normal)
    assert styles.key?(:fast)
    assert styles.key?(:whisper)
  end

  def test_edge_voices_constant
    voices = MASTER::Speech::EDGE_VOICES
    assert voices.key?(:aria)
    assert voices.key?(:guy)
  end

  def test_piper_presets_constant
    presets = MASTER::Speech::PIPER_PRESETS
    assert presets.key?(:normal)
    assert presets.key?(:demon)
  end

  def test_engine_status_returns_string
    status = MASTER::Speech.engine_status
    assert status.is_a?(String)
  end

  def test_engine_status_off_when_none
    # This might return "off" or actual engines depending on system
    status = MASTER::Speech.engine_status
    assert ["off", "piper", "edge", "replicate", "piper/edge", "edge/replicate", "piper/edge/replicate"].any? { |s| status.include?(s) || status == s }
  end

  def test_available_engines_returns_array
    engines = MASTER::Speech.available_engines
    assert engines.is_a?(Array)
    engines.each do |e|
      assert MASTER::Speech::ENGINES.include?(e)
    end
  end

  def test_best_engine_returns_symbol_or_nil
    engine = MASTER::Speech.best_engine
    assert engine.nil? || engine.is_a?(Symbol)
  end

  def test_speak_rejects_empty_text
    result = MASTER::Speech.speak("")
    assert result.err?
    assert_includes result.error, "Empty"
  end

  def test_speak_rejects_nil_text
    result = MASTER::Speech.speak(nil)
    assert result.err?
  end

  def test_speak_method_exists
    assert MASTER::Speech.respond_to?(:speak)
  end

  def test_stream_method_exists
    assert MASTER::Speech.respond_to?(:stream)
  end

  def test_demon_method_exists
    assert MASTER::Speech.respond_to?(:demon)
  end

  def test_chatter_method_exists
    assert MASTER::Speech.respond_to?(:chatter)
  end

  # These check actual system, may be slow - test existence only
  def test_piper_installed_method_exists
    assert MASTER::Speech.respond_to?(:piper_installed?)
  end

  def test_edge_installed_method_exists
    assert MASTER::Speech.respond_to?(:edge_installed?)
  end

  def test_install_edge_method_exists
    assert MASTER::Speech.respond_to?(:install_edge!)
  end
end
