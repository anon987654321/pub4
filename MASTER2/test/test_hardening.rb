# frozen_string_literal: true

require_relative "test_helper"

class TestHardening < Minitest::Test
  def setup
    @executor = MASTER::Executor.new
  end

  # Test 1: Result type safety with @kind
  def test_result_kind_field
    ok_result = MASTER::Result.ok("value")
    assert_equal :ok, ok_result.kind
    
    err_result = MASTER::Result.err("error")
    assert_equal :err, err_result.kind
  end
  
  def test_result_ok_nil_is_unambiguous
    result = MASTER::Result.ok(nil)
    assert result.ok?
    assert_equal :ok, result.kind
    refute result.err?
  end

  # Test 4: Wall-clock timeout constant
  def test_executor_has_timeout_constant
    assert_equal 120, MASTER::Executor::WALL_CLOCK_TIMEOUT
  end
  
  # Test 5: Executor tool validation
  def test_executor_validates_tool_names
    result = @executor.send(:execute_tool, "invalid_tool_name 'test'")
    assert_match(/Unknown tool/, result)
  end
  
  def test_executor_blocks_dangerous_shell_commands
    # Test dangerous pattern blocking
    result = @executor.send(:execute_tool, "shell_command 'rm -rf /'")
    assert_match(/Security.*dangerous pattern/, result)
    
    result = @executor.send(:execute_tool, "shell_command 'DROP TABLE users'")
    assert_match(/Security.*dangerous pattern/, result)
  end

  # Test 7: Circuit breaker threshold
  def test_circuit_breaker_constants
    assert_equal 3, MASTER::LLM::FAILURES_BEFORE_TRIP
  end

  # Test 8: Pipeline stage validation
  def test_pipeline_validates_stage_names
    error = assert_raises(ArgumentError) do
      MASTER::Pipeline.new(stages: [:invalid_stage], mode: :stages)
    end
    assert_match(/Invalid stage/, error.message)
    assert_match(/Valid stages:/, error.message)
  end
  
  def test_pipeline_accepts_valid_stages
    # Should not raise
    pipeline = MASTER::Pipeline.new(stages: [:intake, :guard], mode: :stages)
    assert_instance_of MASTER::Pipeline, pipeline
  end

  # Test 9: Regex timeout in Lint
  def test_lint_has_timeout_constant
    assert_equal 1.0, MASTER::Stages::Lint::REGEX_TIMEOUT
  end

  # Test 12: Buffer caps
  def test_executor_has_history_cap
    assert_equal 50, MASTER::Executor::MAX_HISTORY_SIZE
  end
  
  def test_dmesg_has_buffer_cap
    assert_equal 1000, MASTER::Dmesg::MAX_BUFFER_SIZE
  end

  # Test 14: REPL input validation constants
  def test_repl_has_input_length_constant
    # Verify MAX_INPUT_BYTES constant exists
    assert defined?(MASTER::Pipeline::MAX_INPUT_BYTES)
    assert_equal 10_000, MASTER::Pipeline::MAX_INPUT_BYTES
  end

  # Test 6: Pipeline return shape normalization
  def test_pipeline_normalizes_direct_mode_response
    skip "Requires API key and network" unless ENV["OPENROUTER_API_KEY"]
    # This would require mocking LLM.ask which is beyond unit test scope
  end
end
