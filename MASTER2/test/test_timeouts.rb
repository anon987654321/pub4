# frozen_string_literal: true

require_relative "test_helper"

class TestTimeouts < Minitest::Test
  def test_defaults_exist
    assert_equal 10, MASTER::Timeouts.http_open
    assert_equal 30, MASTER::Timeouts.http_read
    assert_equal 30, MASTER::Timeouts.http_write
    assert_equal 120, MASTER::Timeouts.llm_read
    assert_equal 30, MASTER::Timeouts.browser
    assert_equal 30, MASTER::Timeouts.shell
    assert_equal 120, MASTER::Timeouts.executor_wall_clock
    assert_equal 60, MASTER::Timeouts.replicate_create
    assert_equal 300, MASTER::Timeouts.replicate_poll
    assert_equal 2, MASTER::Timeouts.replicate_poll_interval
    assert_equal 600, MASTER::Timeouts.pipeline
    assert_equal 60, MASTER::Timeouts.download
    assert_equal 120, MASTER::Timeouts.tts_stream
  end

  def test_constitution_overrides
    # Constitution file should contain the same values as defaults
    # (since we're using identical values in the constitution)
    config = MASTER::Timeouts.config
    assert_equal 10, config[:http_open]
    assert_equal 120, config[:llm_read]
    assert_equal 30, config[:browser]
  end

  def test_unknown_timeout_raises
    assert_raises(NoMethodError) do
      MASTER::Timeouts.nonexistent_timeout
    end
  end

  def test_respond_to_missing
    assert MASTER::Timeouts.respond_to?(:http_open)
    assert MASTER::Timeouts.respond_to?(:llm_read)
    refute MASTER::Timeouts.respond_to?(:nonexistent_timeout)
  end
end
