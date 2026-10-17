# frozen_string_literal: true

require_relative "../test_helper"
require_relative "../../lib/voice/stt"

class TestVoiceStt < Minitest::Test
  def setup
    @stt = Master::Voice::Stt.build(config: { backend: :null })
  end

  def test_build_null
    assert_equal :null, @stt.backend_name
    refute @stt.available?
  end

  def test_finish_without_start_is_empty
    result = @stt.finish
    assert_equal "", result.text
    refute result.partial?
  end

  def test_utterance_cycle_null
    @stt.start_utterance
    assert @stt.snapshot[:open]
    partial = @stt.feed(Array.new(480, 0.1))
    assert_nil partial
    result = @stt.finish
    assert_equal "", result.text
    assert_equal :null, result.backend
    refute @stt.snapshot[:open]
  end

  def test_reset_closes
    @stt.start_utterance
    @stt.feed(Array.new(100, 0.0))
    @stt.reset!
    refute @stt.snapshot[:open]
    assert_equal 0, @stt.snapshot[:buffered_samples]
  end

  def test_pcm16_accepted
    @stt.start_utterance
    @stt.feed(Array.new(480, 1000))
    result = @stt.finish
    assert_kind_of Master::Voice::Stt::Result, result
  end

  def test_snapshot_frozen
    assert @stt.snapshot.frozen?
  end
end
