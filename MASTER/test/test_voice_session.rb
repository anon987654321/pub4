# frozen_string_literal: true

require_relative "test_helper"
require_relative "../lib/voice/session"

class TestVoiceSession < Minitest::Test
  def setup
    @session = Master::Voice::Session.new
  end

  def test_starts_listening
    assert_equal :listening, @session.state
    assert_equal 0, @session.generation
  end

  def test_speaking_generation_is_playback_generation
    token = @session.speaking!

    assert_equal token, @session.generation
    assert Master::Voice::Playback.generation_active?(token)
  end

  def test_interrupt_invalidates_previous_generation
    token = @session.speaking!
    interrupted = @session.interrupt!

    assert_operator interrupted, :>, token
    refute @session.active?(token)
    assert_equal :interrupted, @session.state
  end

  def test_invalid_state_is_rejected
    assert_raises(ArgumentError) { @session.send(:transition!, :nonsense) }
  end
end
