# frozen_string_literal: true

require_relative "test_helper"

class TestPipeline < Minitest::Test
  def setup
    setup_db
  end

  def test_pipeline_initialization
    pipeline = MASTER::Pipeline.new
    assert pipeline
  end

  def test_pipeline_with_safe_input
    pipeline = MASTER::Pipeline.new(stages: %i[intake guard])
    result = pipeline.call({ text: "Hello world" })
    assert result.ok?, "Pipeline should succeed with safe input"
  end

  def test_pipeline_blocks_dangerous_input
    pipeline = MASTER::Pipeline.new(stages: %i[intake guard])
    result = pipeline.call({ text: "rm -rf /" })
    assert result.err?, "Pipeline should block dangerous input"
  end

  def test_pipeline_preserves_data
    pipeline = MASTER::Pipeline.new(stages: %i[intake guard])
    result = pipeline.call({ text: "test", custom: "data" })
    assert result.ok?
    assert_equal "data", result.value[:custom], "Custom data should be preserved"
  end

  def test_prompt_format
    prompt = MASTER::Pipeline.prompt
    assert_match(/^master\[/, prompt, "Prompt should start with 'master['")
    assert_match(/\]\$ $/, prompt, "Prompt should end with ']$ '")
  end

  def test_prompt_shows_tier
    prompt = MASTER::Pipeline.prompt
    assert_match(/\[(strong|fast|cheap|none)/, prompt, "Prompt should contain a tier")
  end

  def test_prompt_shows_budget
    prompt = MASTER::Pipeline.prompt
    assert_match(/\$\d+\.\d{2}/, prompt, "Prompt should show budget")
  end
end
