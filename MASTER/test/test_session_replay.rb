# frozen_string_literal: true

require_relative "test_helper"
require "json"

class TestSessionReplay < Minitest::Test
  def setup
    @temp_session_dir = Dir.mktmpdir
    @original_sessions_dir = MASTER::Paths.instance_variable_get(:@sessions)
    MASTER::Paths.instance_variable_set(:@sessions, @temp_session_dir)
  end

  def teardown
    MASTER::Paths.instance_variable_set(:@sessions, @original_sessions_dir)
    FileUtils.rm_rf(@temp_session_dir) if @temp_session_dir && Dir.exist?(@temp_session_dir)
  end

  def test_replay_with_mock_session
    skip "SessionReplay not available" unless defined?(MASTER::SessionReplay)

    # Create a mock session
    session_id = "test-session-123"
    session_data = {
      id: session_id,
      created_at: Time.now.utc.iso8601,
      history: [
        { role: :user, content: "Hello", timestamp: Time.now.utc.iso8601 },
        { role: :assistant, content: "Hi there!", cost: 0.01, model: "claude-3", timestamp: Time.now.utc.iso8601 }
      ],
      metadata: {}
    }

    # Save the mock session
    MASTER::Memory.save_session(session_id, session_data)

    # Replay it
    result = MASTER::SessionReplay.replay(session_id, format: :terminal)
    assert result.ok?, "Replay should succeed"
    assert_equal 2, result.value[:messages]
    assert result.value[:cost] >= 0.01
  end

  def test_replay_nonexistent_session
    skip "SessionReplay not available" unless defined?(MASTER::SessionReplay)

    result = MASTER::SessionReplay.replay("nonexistent-id")
    assert result.err?, "Should return error for nonexistent session"
    assert_match(/not found/, result.error)
  end

  def test_replay_empty_session
    skip "SessionReplay not available" unless defined?(MASTER::SessionReplay)

    session_id = "empty-session"
    session_data = {
      id: session_id,
      created_at: Time.now.utc.iso8601,
      history: [],
      metadata: {}
    }

    MASTER::Memory.save_session(session_id, session_data)

    result = MASTER::SessionReplay.replay(session_id)
    assert result.err?, "Should return error for empty session"
    assert_match(/Empty session/, result.error)
  end

  def test_list_with_summaries
    skip "SessionReplay not available" unless defined?(MASTER::SessionReplay)

    # Create multiple mock sessions
    3.times do |i|
      session_id = "session-#{i}"
      session_data = {
        id: session_id,
        created_at: Time.now.utc.iso8601,
        history: [
          { role: :user, content: "Test #{i}", cost: 0.01 * i, timestamp: Time.now.utc.iso8601 }
        ],
        metadata: {}
      }
      MASTER::Memory.save_session(session_id, session_data)
    end

    result = MASTER::SessionReplay.list_with_summaries
    assert result.ok?, "List should succeed"
    assert_equal 3, result.value.size
    assert result.value.first.key?(:short_id)
    assert result.value.first.key?(:messages)
    assert result.value.first.key?(:cost)
  end

  def test_diff_sessions
    skip "SessionReplay not available" unless defined?(MASTER::SessionReplay)

    # Create two sessions
    session_a = "session-a"
    session_b = "session-b"

    MASTER::Memory.save_session(session_a, {
      id: session_a,
      created_at: Time.now.utc.iso8601,
      history: [
        { role: :user, content: "Test A", cost: 0.05, timestamp: Time.now.utc.iso8601 }
      ],
      metadata: {}
    })

    MASTER::Memory.save_session(session_b, {
      id: session_b,
      created_at: Time.now.utc.iso8601,
      history: [
        { role: :user, content: "Test B1", cost: 0.02, timestamp: Time.now.utc.iso8601 },
        { role: :assistant, content: "Response B", cost: 0.03, timestamp: Time.now.utc.iso8601 }
      ],
      metadata: {}
    })

    result = MASTER::SessionReplay.diff_sessions(session_a, session_b)
    assert result.ok?, "Diff should succeed"
    assert_equal 1, result.value[:session_a][:messages]
    assert_equal 2, result.value[:session_b][:messages]
    assert result.value[:cost_diff].is_a?(Numeric)
  end

  def test_replay_json_format
    skip "SessionReplay not available" unless defined?(MASTER::SessionReplay)

    session_id = "json-test"
    session_data = {
      id: session_id,
      created_at: Time.now.utc.iso8601,
      history: [
        { role: :user, content: "Test", timestamp: Time.now.utc.iso8601 }
      ],
      metadata: {}
    }

    MASTER::Memory.save_session(session_id, session_data)

    result = MASTER::SessionReplay.replay(session_id, format: :json)
    assert result.ok?, "JSON format should succeed"
    assert result.value.is_a?(Hash)
    assert_equal session_id, result.value[:id]
  end

  def test_replay_markdown_format
    skip "SessionReplay not available" unless defined?(MASTER::SessionReplay)

    session_id = "md-test"
    session_data = {
      id: session_id,
      created_at: Time.now.utc.iso8601,
      history: [
        { role: :user, content: "Test question", timestamp: Time.now.utc.iso8601 },
        { role: :assistant, content: "Test answer", cost: 0.01, timestamp: Time.now.utc.iso8601 }
      ],
      metadata: {}
    }

    MASTER::Memory.save_session(session_id, session_data)

    result = MASTER::SessionReplay.replay(session_id, format: :markdown)
    assert result.ok?, "Markdown format should succeed"
    assert result.value.is_a?(String)
    assert result.value.include?("# Session")
    assert result.value.include?("## Turn")
  end

  def test_unknown_format
    skip "SessionReplay not available" unless defined?(MASTER::SessionReplay)

    session_id = "format-test"
    session_data = {
      id: session_id,
      created_at: Time.now.utc.iso8601,
      history: [{ role: :user, content: "Test", timestamp: Time.now.utc.iso8601 }],
      metadata: {}
    }

    MASTER::Memory.save_session(session_id, session_data)

    result = MASTER::SessionReplay.replay(session_id, format: :unknown)
    assert result.err?, "Should return error for unknown format"
    assert_match(/Unknown format/, result.error)
  end

  def test_calculate_duration
    skip "SessionReplay not available" unless defined?(MASTER::SessionReplay)

    # Test with valid timestamps
    history = [
      { timestamp: "2024-01-01T10:00:00Z" },
      { timestamp: "2024-01-01T10:05:30Z" }
    ]

    duration = MASTER::SessionReplay.send(:calculate_duration, history)
    assert duration.is_a?(String)
    assert duration.include?("m") || duration.include?("s")
  end

  def test_empty_session_list
    skip "SessionReplay not available" unless defined?(MASTER::SessionReplay)

    result = MASTER::SessionReplay.list_with_summaries
    assert result.ok?, "Empty list should succeed"
    assert_equal 0, result.value.size
  end
end
