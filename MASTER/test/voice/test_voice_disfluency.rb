# frozen_string_literal: true

require_relative "../test_helper"
require "minitest/mock"
require "voice/disfluency"

class TestVoiceDisfluency < Minitest::Test
  D = Master::Voice::Disfluency

  def test_default_policy_keeps_synthetic_disfluencies_off
    cfg = Master::Voice::Policy.data.fetch("disfluencies")
    assert_equal false, cfg.fetch("enabled")
    assert_equal false, D::DEFAULTS.fetch("enabled")
    assert_operator D::DEFAULTS.fetch("min_words"), :>, 0
  end

  def test_default_speech_preserves_the_words_supplied_for_synthesis
    text = "I think we should keep this small for now."
    original = ENV["MASTER_TTS_DISFLUENCIES"]
    ENV.delete("MASTER_TTS_DISFLUENCIES")
    assert_equal text, D.apply(text, source: text)
  ensure
    original ? ENV["MASTER_TTS_DISFLUENCIES"] = original : ENV.delete("MASTER_TTS_DISFLUENCIES")
  end

  def test_hedged_first_person_speech_can_have_a_natural_hesitation
    text = "I think we should keep this small for now."
    config = D::DEFAULTS.merge(
      "enabled" => true,
      "probability" => 1.0,
      "stutter_probability" => 0.0,
      "fillers" => ["um"],
    )
    spoken = Master::Voice::Policy.stub(:data, { "disfluencies" => config }) do
      D.apply(text, source: text)
    end

    assert_equal "I, um, think we should keep this small for now.", spoken
  end

  def test_first_person_onset_can_stutter_without_rewriting_the_claim
    text = "I think this is probably the right direction."
    config = D::DEFAULTS.merge("enabled" => true, "probability" => 1.0, "stutter_probability" => 1.0)
    spoken = Master::Voice::Policy.stub(:data, { "disfluencies" => config }) do
      D.apply(text, source: text)
    end

    assert_equal "I- I think this is probably the right direction.", spoken
  end

  def test_technical_prose_and_lists_are_spared
    config = D::DEFAULTS.merge("enabled" => true, "probability" => 1.0)
    Master::Voice::Policy.stub(:data, { "disfluencies" => config }) do
      command = "I think run `git status` before changing anything."
      list = "- I think we should keep this small for now."
      assert_equal command, D.apply(command, source: command)
      assert_equal list, D.apply(list, source: list)
    end
  end

  def test_operator_can_disable_the_layer_without_changing_voice
    text = "I think we should keep this small for now."
    old = ENV["MASTER_TTS_DISFLUENCIES"]
    ENV["MASTER_TTS_DISFLUENCIES"] = "0"
    assert_equal text, D.apply(text, source: text)
  ensure
    old.nil? ? ENV.delete("MASTER_TTS_DISFLUENCIES") : ENV["MASTER_TTS_DISFLUENCIES"] = old
  end
end
