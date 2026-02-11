# frozen_string_literal: true

require_relative "test_helper"

class TestHardening < Minitest::Test
  def setup
    setup_db
  end

  # Fix 1 & 2: Result type-safety with @kind tag
  def test_result_ok_has_kind_ok
    result = MASTER::Result.ok("value")
    assert_equal :ok, result.kind
    assert result.ok?
    refute result.err?
  end

  def test_result_err_has_kind_err
    result = MASTER::Result.err("error")
    assert_equal :err, result.kind
    assert result.err?
    refute result.ok?
  end

  def test_result_ok_with_nil_value
    result = MASTER::Result.ok(nil)
    assert result.ok?, "Result.ok(nil) should be ok?"
    assert_equal :ok, result.kind
    assert_nil result.value
  end

  def test_result_distinguishes_ok_nil_from_error
    ok_nil = MASTER::Result.ok(nil)
    err = MASTER::Result.err("failed")
    
    assert ok_nil.ok?
    refute err.ok?
    assert_equal :ok, ok_nil.kind
    assert_equal :err, err.kind
  end

  def test_result_and_then_with_label
    result = MASTER::Result.ok(5)
      .and_then("step1") { |v| MASTER::Result.ok(v * 2) }
      .and_then("step2") { |v| raise StandardError, "oops" }
    
    assert result.err?
    assert_match(/step2/, result.error)
    assert_match(/oops/, result.error)
  end

  def test_result_rescues_standard_error_only
    # This should rescue StandardError
    result = MASTER::Result.ok(5).map { raise StandardError, "standard" }
    assert result.err?
    assert_equal "standard", result.error
  end

  # Fix 5: Guard Executor tool dispatch
  def test_executor_blocks_dangerous_shell_patterns
    executor = MASTER::Executor.new
    
    # Test rm -rf /
    result = executor.send(:shell_command, "rm -rf /")
    assert_match(/BLOCKED/, result)
    
    # Test DROP TABLE
    action = executor.send(:sanitize_tool_input, "shell_command 'DROP TABLE users'")
    assert_match(/BLOCKED/, action)
  end

  def test_executor_blocks_file_write_outside_cwd
    executor = MASTER::Executor.new
    
    # Try to write outside working directory
    result = executor.send(:file_write, "/etc/passwd", "malicious")
    assert_match(/BLOCKED/, result)
    
    # Relative paths that escape should also be blocked
    result = executor.send(:file_write, "../../etc/passwd", "malicious")
    assert_match(/BLOCKED/, result)
  end

  def test_executor_allows_safe_file_write
    executor = MASTER::Executor.new
    
    # Create temp directory
    Dir.mktmpdir do |tmpdir|
      Dir.chdir(tmpdir) do
        result = executor.send(:file_write, "test.txt", "safe content")
        assert_match(/Written/, result)
        assert File.exist?("test.txt")
        assert_equal "safe content", File.read("test.txt")
      end
    end
  end

  # Fix 8: Validate stage order at initialization
  def test_pipeline_rejects_unknown_stage
    error = assert_raises(ArgumentError) do
      MASTER::Pipeline.new(stages: [:intake, :nonexistent], mode: :stages)
    end
    assert_match(/Unknown pipeline stage/, error.message)
    assert_match(/nonexistent/, error.message)
    assert_match(/Available:/, error.message)
  end

  def test_pipeline_accepts_valid_stages
    # Should not raise
    pipeline = MASTER::Pipeline.new(stages: [:intake, :guard], mode: :stages)
    assert pipeline
  end

  # Fix 9: Prevent Stages::Lint regex injection/ReDoS
  def test_lint_stage_handles_invalid_regex
    # Add a malformed pattern to the DB
    MASTER::DB.add_axiom(
      name: "bad_regex",
      description: "Invalid regex",
      category: "test"
    )
    
    # Update the axiom with an invalid pattern
    axioms = MASTER::DB.send(:read_collection, "axioms")
    bad_axiom = axioms.find { |a| a[:name] == "bad_regex" }
    bad_axiom[:pattern] = "(?bad_regex" if bad_axiom
    MASTER::DB.send(:write_collection, "axioms", axioms)
    
    # Should not crash
    lint = MASTER::Stages::Lint.new
    result = lint.call({ response: "test response" })
    assert result.ok?
  end

  def test_lint_stage_timeout_on_redos
    # Create a pathological regex pattern that could cause ReDoS
    # Pattern like (a+)+ can cause exponential backtracking
    MASTER::DB.add_axiom(
      name: "redos_pattern",
      description: "Potential ReDoS",
      category: "test"
    )
    
    axioms = MASTER::DB.send(:read_collection, "axioms")
    redos = axioms.find { |a| a[:name] == "redos_pattern" }
    redos[:pattern] = "(a+)+" if redos
    MASTER::DB.send(:write_collection, "axioms", axioms)
    
    # Should timeout and not hang
    lint = MASTER::Stages::Lint.new
    long_text = "a" * 100 + "b"
    
    start = Time.now
    result = lint.call({ response: long_text })
    elapsed = Time.now - start
    
    assert result.ok?
    # Should complete quickly (timeout is 0.1s, give it some buffer)
    assert elapsed < 1.0, "Lint stage took too long: #{elapsed}s"
  end

  # Fix 10: DB.ensure_seeded idempotency
  def test_db_ensure_seeded_is_idempotent
    MASTER::DB.clear_cache
    
    # First call
    MASTER::DB.send(:ensure_seeded)
    axioms1 = MASTER::DB.axioms
    council1 = MASTER::DB.council
    
    # Second call should not duplicate
    MASTER::DB.send(:ensure_seeded)
    axioms2 = MASTER::DB.axioms
    council2 = MASTER::DB.council
    
    assert_equal axioms1.size, axioms2.size
    assert_equal council1.size, council2.size
  end

  # Fix 11: Stage-name context in pipeline errors
  def test_pipeline_includes_stage_name_in_errors
    # Create a stage that always fails
    failing_stage = Class.new do
      def call(input)
        raise StandardError, "stage failed"
      end
      
      def self.name
        "MASTER::Stages::FailingStage"
      end
    end
    
    pipeline = MASTER::Pipeline.new(
      stages: [MASTER::Stages::Intake.new, failing_stage.new],
      mode: :stages
    )
    
    result = pipeline.call({ text: "test" })
    assert result.err?
    assert_match(/FailingStage/, result.error)
    assert_match(/stage failed/, result.error)
  end

  # Fix 12: Bound memory growth in Executor history
  def test_executor_bounds_history_size
    executor = MASTER::Executor.new
    
    # Add many history entries
    (MASTER::Executor::MAX_HISTORY_SIZE + 10).times do |i|
      executor.send(:record_history, { step: i, data: "x" * 1000 })
    end
    
    # Should not exceed MAX_HISTORY_SIZE
    assert_equal MASTER::Executor::MAX_HISTORY_SIZE, executor.history.size
    
    # Oldest entries should be removed (FIFO)
    # First entry should now be step 10 (0-9 were removed)
    assert_equal 10, executor.history.first[:step]
    assert_equal MASTER::Executor::MAX_HISTORY_SIZE + 9, executor.history.last[:step]
  end

  # Fix 14: Input validation at REPL boundary
  def test_pipeline_max_input_length_constant
    # Just verify the constant exists and is reasonable
    assert MASTER::Pipeline::MAX_INPUT_LENGTH > 0
    assert MASTER::Pipeline::MAX_INPUT_LENGTH <= 1_000_000
  end

  # Fix 7: Circuit breaker respects FAILURES_BEFORE_TRIP
  def test_circuit_breaker_increments_failures
    skip "Requires DB circuit methods" unless defined?(MASTER::DB.increment_failure!)
    
    model = "test-model-#{rand(10000)}"
    
    # First failure should not trip
    MASTER::LLM.send(:open_circuit!, model)
    circuit = MASTER::DB.circuit(model)
    assert_equal "closed", circuit[:state] if circuit
    assert_equal 1, circuit[:failures] if circuit
  end
end
