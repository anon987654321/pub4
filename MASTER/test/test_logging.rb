# frozen_string_literal: true

require "minitest/autorun"
require_relative "../lib/master"

class TestLogging < Minitest::Test
  def setup
    @original_output = MASTER::Logging.output
    @original_level = MASTER::Logging.level
    @original_format = MASTER::Logging.format
    @buffer = StringIO.new
    MASTER::Logging.output = @buffer
  end

  def teardown
    MASTER::Logging.output = @original_output
    MASTER::Logging.level = @original_level
    MASTER::Logging.format = @original_format
  end

  # Level tests
  def test_levels_constant
    levels = MASTER::Logging::LEVELS
    assert_equal 0, levels[:debug]
    assert_equal 1, levels[:info]
    assert_equal 2, levels[:warn]
    assert_equal 3, levels[:error]
    assert_equal 4, levels[:fatal]
  end

  def test_level_accessor
    MASTER::Logging.level = :debug
    assert_equal :debug, MASTER::Logging.level
  end

  def test_level_filtering
    MASTER::Logging.level = :warn
    MASTER::Logging.format = :human
    
    MASTER::Logging.debug("debug message")
    MASTER::Logging.info("info message")
    MASTER::Logging.warn("warn message")
    
    output = @buffer.string
    refute_includes output, "debug message"
    refute_includes output, "info message"
    assert_includes output, "warn message"
  end

  # Format tests
  def test_human_format
    MASTER::Logging.level = :info
    MASTER::Logging.format = :human
    
    MASTER::Logging.info("test message")
    
    output = @buffer.string
    assert_includes output, "test message"
    assert_includes output, "I" # INFO prefix
  end

  def test_json_format
    MASTER::Logging.level = :info
    MASTER::Logging.format = :json
    
    MASTER::Logging.info("test message", foo: "bar")
    
    output = @buffer.string
    parsed = JSON.parse(output)
    assert_equal "INFO", parsed["level"]
    assert_equal "test message", parsed["message"]
    assert_equal "bar", parsed["foo"]
  end

  # Context tests
  def test_context_included_in_output
    MASTER::Logging.level = :info
    MASTER::Logging.format = :json
    
    MASTER::Logging.info("with context", user_id: 123, action: "test")
    
    output = @buffer.string
    parsed = JSON.parse(output)
    assert_equal 123, parsed["user_id"]
    assert_equal "test", parsed["action"]
  end

  # Request ID tests
  def test_with_request_id
    MASTER::Logging.level = :info
    MASTER::Logging.format = :json
    
    MASTER::Logging.with_request_id("abc123") do
      MASTER::Logging.info("traced message")
    end
    
    output = @buffer.string
    parsed = JSON.parse(output)
    assert_equal "abc123", parsed["request_id"]
  end

  def test_request_id_auto_generated
    MASTER::Logging.level = :info
    MASTER::Logging.format = :json
    
    MASTER::Logging.with_request_id do
      MASTER::Logging.info("auto traced")
    end
    
    output = @buffer.string
    parsed = JSON.parse(output)
    assert parsed["request_id"]
    assert_equal 16, parsed["request_id"].length  # hex(8) = 16 chars
  end

  def test_request_id_restored_after_block
    MASTER::Logging.request_id = "outer"
    
    MASTER::Logging.with_request_id("inner") do
      assert_equal "inner", MASTER::Logging.request_id
    end
    
    assert_equal "outer", MASTER::Logging.request_id
    MASTER::Logging.request_id = nil
  end

  # Timed tests
  def test_timed_logs_duration
    MASTER::Logging.level = :info
    MASTER::Logging.format = :json
    
    result = MASTER::Logging.timed("test operation") do
      sleep 0.01
      42
    end
    
    assert_equal 42, result
    
    output = @buffer.string
    parsed = JSON.parse(output)
    assert parsed["duration_ms"]
    assert parsed["duration_ms"] >= 10
  end

  def test_timed_logs_error_on_exception
    MASTER::Logging.level = :error
    MASTER::Logging.format = :json
    
    assert_raises(RuntimeError) do
      MASTER::Logging.timed("failing op") do
        raise "boom"
      end
    end
    
    output = @buffer.string
    parsed = JSON.parse(output)
    assert_equal "ERROR", parsed["level"]
    assert_includes parsed["message"], "failed"
    assert_equal "boom", parsed["error"]
  end

  # Convenience methods
  def test_llm_call_logging
    MASTER::Logging.level = :info
    MASTER::Logging.format = :json
    
    MASTER::Logging.llm_call(
      model: "gpt-4",
      tokens_in: 100,
      tokens_out: 50,
      cost: 0.01,
      duration_ms: 500,
      success: true
    )
    
    output = @buffer.string
    parsed = JSON.parse(output)
    assert_equal "gpt-4", parsed["model"]
    assert_equal 100, parsed["tokens_in"]
    assert_equal 0.01, parsed["cost"]
  end

  def test_tool_exec_success
    MASTER::Logging.level = :debug
    MASTER::Logging.format = :json
    
    MASTER::Logging.tool_exec(tool: "file_read", args: "/tmp/x", duration_ms: 5, success: true)
    
    output = @buffer.string
    parsed = JSON.parse(output)
    assert_equal "file_read", parsed["tool"]
  end

  def test_tool_exec_failure
    MASTER::Logging.level = :warn
    MASTER::Logging.format = :json
    
    MASTER::Logging.tool_exec(tool: "shell", args: "cmd", duration_ms: 10, success: false, error: "denied")
    
    output = @buffer.string
    parsed = JSON.parse(output)
    assert_equal "WARN", parsed["level"]
    assert_equal "denied", parsed["error"]
  end

  # All log levels work
  def test_all_levels_log
    MASTER::Logging.level = :debug
    MASTER::Logging.format = :human
    
    MASTER::Logging.debug("d")
    MASTER::Logging.info("i")
    MASTER::Logging.warn("w")
    MASTER::Logging.error("e")
    MASTER::Logging.fatal("f")
    
    output = @buffer.string
    assert_includes output, "d"
    assert_includes output, "i"
    assert_includes output, "w"
    assert_includes output, "e"
    assert_includes output, "f"
  end
end
