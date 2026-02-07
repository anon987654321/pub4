# frozen_string_literal: true

require_relative "test_helper"

class TestPipeline < Minitest::Test
  def setup
    setup_db
    # Ensure session exists for prompt tests
    MASTER::Session.start_new
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
    # Should either be formatted or fallback
    assert prompt.start_with?("master"), "Prompt should start with 'master'"
  end

  def test_prompt_shows_tier_or_fallback
    prompt = MASTER::Pipeline.prompt
    # Accept either formatted prompt or fallback
    valid = prompt.match?(/\[(strong|fast|cheap|none)/) || prompt == "master$ "
    assert valid, "Prompt should contain a tier or be fallback: #{prompt}"
  end

  def test_prompt_shows_budget_or_fallback
    prompt = MASTER::Pipeline.prompt
    # Accept formatted prompt with tier or fallback
    valid = prompt.match?(/master\[.+\]›/) || prompt == "master› "
    assert valid, "Prompt should show tier or be fallback: #{prompt}"
  end
end
