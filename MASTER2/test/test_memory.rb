# frozen_string_literal: true

require "minitest/autorun"
require_relative "../lib/master"

class TestMemorySearch < Minitest::Test
  def setup
    # Clear any existing sessions
    MASTER::Memory.clear
  end

  def test_search_returns_array
    result = MASTER::Memory.search("test query")
    assert result.is_a?(Array)
  end

  def test_search_empty_query
    result = MASTER::Memory.search("")
    assert_equal [], result
  end

  def test_search_nil_query
    result = MASTER::Memory.search(nil)
    assert_equal [], result
  end

  def test_search_respects_limit
    result = MASTER::Memory.search("something", limit: 5)
    assert result.size <= 5
  end

  def test_compress_keeps_first_and_last
    history = (1..20).map { |i| { role: :user, content: "message #{i}" } }
    
    compressed = MASTER::Memory.compress(history)
    
    # Should keep first 2 and last 8
    assert_equal 10, compressed.size
    assert_equal "message 1", compressed.first[:content]
    assert_equal "message 2", compressed[1][:content]
    assert_equal "message 20", compressed.last[:content]
  end

  def test_compress_returns_original_if_short
    history = (1..5).map { |i| { role: :user, content: "message #{i}" } }
    
    compressed = MASTER::Memory.compress(history)
    
    assert_equal 5, compressed.size
  end

  def test_store_and_fetch
    MASTER::Memory.store(:test_key, { data: "value" })
    result = MASTER::Memory.fetch(:test_key)
    
    assert_equal({ data: "value" }, result)
  end

  def test_fetch_missing_key
    result = MASTER::Memory.fetch(:nonexistent)
    assert_nil result
  end

  def test_all_returns_copy
    MASTER::Memory.store(:a, 1)
    MASTER::Memory.store(:b, 2)
    
    all = MASTER::Memory.all
    assert all.key?(:a)
    assert all.key?(:b)
    
    # Verify it's a copy
    all[:c] = 3
    refute MASTER::Memory.fetch(:c)
  end

  def test_size
    MASTER::Memory.clear
    MASTER::Memory.store(:x, 1)
    MASTER::Memory.store(:y, 2)
    
    assert_equal 2, MASTER::Memory.size
  end

  def test_clear
    MASTER::Memory.store(:key, "value")
    MASTER::Memory.clear
    
    assert_equal 0, MASTER::Memory.size
  end

  # Session persistence
  def test_save_and_load_session
    test_id = "test_#{Time.now.to_i}"
    data = { messages: [{ role: :user, content: "hello" }] }
    
    path = MASTER::Memory.save_session(test_id, data)
    assert File.exist?(path)
    
    loaded = MASTER::Memory.load_session(test_id)
    assert_equal "hello", loaded[:messages].first[:content]
    
    # Cleanup
    File.delete(path) if File.exist?(path)
  end

  def test_load_missing_session
    result = MASTER::Memory.load_session("nonexistent_session_id")
    assert_nil result
  end

  def test_list_sessions
    sessions = MASTER::Memory.list_sessions
    assert sessions.is_a?(Array)
  end
end
