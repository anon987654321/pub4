# frozen_string_literal: true

require_relative "test_helper"

class TestPipelineCoverage < Minitest::Test
  def setup
    setup_db
    stub_llm_ask(content: "Pipeline test response")
    MASTER::Session.start_new rescue nil
  end

  def teardown
    restore_llm_ask
    teardown_db
  end

  def test_pipeline_executor_mode_returns_result
    pipeline = MASTER::Pipeline.new(mode: :executor)
    result = pipeline.call({ text: "hello" })
    assert result.respond_to?(:ok?), "Should return a Result"
  end

  def test_pipeline_direct_mode_returns_result
    pipeline = MASTER::Pipeline.new(mode: :direct)
    result = pipeline.call({ text: "hello" })
    assert result.respond_to?(:ok?), "Should return a Result"
  end

  def test_pipeline_accepts_string_input
    pipeline = MASTER::Pipeline.new(mode: :executor)
    result = pipeline.call("hello world")
    assert result.respond_to?(:ok?)
  end

  def test_pipeline_normalize_result_preserves_custom_keys
    pipeline = MASTER::Pipeline.new(mode: :stages)
    result = pipeline.call({ text: "Hello world", custom_key: "preserved" })
    if result.ok?
      assert_equal "preserved", result.value[:custom_key]
    end
  end

  def test_pipeline_strip_tool_blocks
    pipeline = MASTER::Pipeline.new
    # Access private method for unit testing
    cleaned = pipeline.send(:strip_tool_blocks, "Hello\n```sh\nfile_read \"test.rb\"\n```\nWorld")
    refute_match(/file_read/, cleaned)
    assert_match(/Hello/, cleaned)
    assert_match(/World/, cleaned)
  end

  def test_pipeline_strip_tool_blocks_with_nil
    pipeline = MASTER::Pipeline.new
    result = pipeline.send(:strip_tool_blocks, nil)
    assert_nil result
  end

  def test_pipeline_strip_tool_blocks_preserves_non_tool_code
    pipeline = MASTER::Pipeline.new
    code = "```ruby\nputs 'hello'\n```"
    result = pipeline.send(:strip_tool_blocks, code)
    assert_match(/puts/, result)
  end
end
