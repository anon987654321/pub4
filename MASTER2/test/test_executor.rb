# frozen_string_literal: true

require "minitest/autorun"
require_relative "../lib/master"

class TestExecutor < Minitest::Test
  def setup
    @executor = MASTER::Executor.new
  end

  # Pattern selection tests
  def test_patterns_constant_exists
    assert_equal %i[react pre_act rewoo reflexion], MASTER::Executor::PATTERNS
  end

  def test_max_steps_default
    assert_equal 15, MASTER::Executor::MAX_STEPS
  end

  def test_tools_hash_exists
    tools = MASTER::Executor::TOOLS
    assert tools.key?(:ask_llm)
    assert tools.key?(:file_read)
    assert tools.key?(:shell_command)
    assert tools.key?(:council_review)
    assert_equal 12, tools.size
  end

  # Pattern selection heuristics - now LLM-based
  def test_select_pattern_react_for_simple
    MASTER::LLM.stub :ask, MASTER::Result.ok(content: "react") do
      pattern = @executor.select_pattern("What is Ruby?")
      assert_equal :react, pattern
    end
  end

  def test_select_pattern_pre_act_for_multi_step
    MASTER::LLM.stub :ask, MASTER::Result.ok(content: "pre_act") do
      pattern = @executor.select_pattern("First read the file, then analyze it, finally fix issues")
      assert_equal :pre_act, pattern
    end
  end

  def test_select_pattern_pre_act_for_build_task
    MASTER::LLM.stub :ask, MASTER::Result.ok(content: "pre_act") do
      pattern = @executor.select_pattern("Build a CLI tool and add tests")
      assert_equal :pre_act, pattern
    end
  end

  def test_select_pattern_rewoo_for_reasoning
    MASTER::LLM.stub :ask, MASTER::Result.ok(content: "rewoo") do
      pattern = @executor.select_pattern("Explain the difference between modules and classes")
      assert_equal :rewoo, pattern
    end
  end

  def test_select_pattern_reflexion_for_fix
    MASTER::LLM.stub :ask, MASTER::Result.ok(content: "reflexion") do
      pattern = @executor.select_pattern("Fix the bug in parser.rb")
      assert_equal :reflexion, pattern
    end
  end

  def test_select_pattern_reflexion_for_careful
    MASTER::LLM.stub :ask, MASTER::Result.ok(content: "reflexion") do
      pattern = @executor.select_pattern("Refactor carefully without breaking tests")
      assert_equal :reflexion, pattern
    end
  end

  def test_select_pattern_direct_for_simple_questions
    MASTER::LLM.stub :ask, MASTER::Result.ok(content: "direct") do
      pattern = @executor.select_pattern("Hello!")
      assert_equal :direct, pattern
    end
  end

  def test_select_pattern_fallback_on_llm_error
    MASTER::LLM.stub :ask, MASTER::Result.err("API error") do
      pattern = @executor.select_pattern("Some task")
      assert_equal :react, pattern
    end
  end

  def test_select_pattern_fallback_on_invalid_response
    MASTER::LLM.stub :ask, MASTER::Result.ok(content: "invalid_pattern") do
      pattern = @executor.select_pattern("Some task")
      assert_equal :react, pattern
    end
  end

  # Simple query detection - now based on @pattern
  def test_simple_query_true_when_pattern_is_direct
    @executor.instance_variable_set(:@pattern, :direct)
    assert @executor.send(:simple_query?, "What is 2+2?")
  end

  def test_simple_query_false_when_pattern_is_react
    @executor.instance_variable_set(:@pattern, :react)
    refute @executor.send(:simple_query?, "Read the config file")
  end

  def test_simple_query_false_when_pattern_is_pre_act
    @executor.instance_variable_set(:@pattern, :pre_act)
    refute @executor.send(:simple_query?, "First build, then test")
  end

  def test_simple_query_false_when_pattern_is_reflexion
    @executor.instance_variable_set(:@pattern, :reflexion)
    refute @executor.send(:simple_query?, "Fix the bug carefully")
  end

  # Response parsing
  def test_parse_response_extracts_thought_and_action
    text = <<~RESPONSE
      Thought: I need to read the file first
      Action: file_read "config.yml"
    RESPONSE

    parsed = @executor.send(:parse_response, text)
    assert_equal "I need to read the file first", parsed[:thought]
    assert_equal 'file_read "config.yml"', parsed[:action]
  end

  def test_parse_response_handles_answer
    text = "Thought: Done\nAction: ANSWER: The result is 42"
    parsed = @executor.send(:parse_response, text)
    assert_match(/ANSWER/, parsed[:action])
  end

  def test_parse_response_fallback_for_malformed
    text = "Just some text without structure"
    parsed = @executor.send(:parse_response, text)
    assert_equal "Continuing", parsed[:thought]
    assert_includes parsed[:action], "ask_llm"
  end

  # Tool execution (mocked)
  def test_execute_tool_file_read_missing
    result = @executor.send(:file_read, "/nonexistent/path/file.txt")
    assert_includes result, "not found"
  end

  def test_execute_tool_file_read_exists
    # Create temp file
    require "tempfile"
    file = Tempfile.new("test")
    file.write("Hello World")
    file.close

    result = @executor.send(:file_read, file.path)
    assert_includes result, "Hello World"

    file.unlink
  end

  def test_execute_tool_shell_command
    result = @executor.send(:shell_command, "echo hello")
    assert_includes result.downcase, "hello"
  end

  def test_execute_tool_unknown
    result = @executor.send(:execute_tool, "unknown_tool arg")
    assert_includes result, "Unknown tool"
  end

  # History and step tracking
  def test_initial_state
    executor = MASTER::Executor.new
    assert_equal [], executor.history
    assert_equal 0, executor.step
  end

  def test_custom_max_steps
    executor = MASTER::Executor.new(max_steps: 5)
    assert_equal 5, executor.instance_variable_get(:@max_steps)
  end

  # Class method delegation
  def test_class_call_method_exists
    assert MASTER::Executor.respond_to?(:call)
  end
end
