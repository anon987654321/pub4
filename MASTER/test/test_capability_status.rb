# frozen_string_literal: true

require "minitest/autorun"
require "master"
require_relative "../lib/operator/services"

class CapabilityStatusTest < Minitest::Test
  def test_voice_status_reports_retained_runtime_failure
    speech = Master::Voice::Speech
    playback = Master::Voice::Playback
    original_speech = speech.instance_variable_get(:@last_error)
    original_playback = playback.instance_variable_get(:@last_error)

    speech.instance_variable_set(:@last_error, "edge socket produced empty audio")
    playback.instance_variable_set(:@last_error, "audio playback failed — afplay")
    status = Master::Operator.status("voice")["voice"]

    assert_match(/Adegraded:/, status)
    assert_match(/edge socket produced empty audio|audio playback failed/, status)
  ensure
    speech.instance_variable_set(:@last_error, original_speech)
    playback.instance_variable_set(:@last_error, original_playback)
  end
end
