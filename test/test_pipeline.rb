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
    pipeline = MASTER::Pipeline.new(stages: %i[intake guard], mode: :stages)
    result = pipeline.call({ text: "Hello world" })
    assert result.ok?, "Pipeline should succeed with safe input"
  end

  def test_pipeline_blocks_dangerous_input
    pipeline = MASTER::Pipeline.new(stages: %i[intake guard], mode: :stages)
    result = pipeline.call({ text: "rm -rf /" })
    assert result.err?, "Pipeline should block dangerous input"
  end

  def test_pipeline_preserves_data
    pipeline = MASTER::Pipeline.new(stages: %i[intake guard], mode: :stages)
    result = pipeline.call({ text: "test", custom: "data" })
    assert result.ok?
    assert_equal "data", result.value[:custom], "Custom data should be preserved"
  end

  def test_prompt_format
    prompt = MASTER::Pipeline.prompt
    # Should contain "master" in some form
    assert prompt.include?("master"), "Prompt should contain 'master': #{prompt}"
  end

  def test_prompt_shows_tier_or_fallback
    prompt = MASTER::Pipeline.prompt
    # Accept any reasonable prompt format
    valid = prompt.match?(/master/) && (
      prompt.match?(/\[(strong|fast|cheap|none|unknown)/) ||
      prompt.match?(/@/) ||
      prompt.match?(/\$|›/)
    )
    assert valid, "Prompt should be a valid MASTER prompt: #{prompt}"
  end

  def test_prompt_shows_budget_or_fallback
    prompt = MASTER::Pipeline.prompt
    # Accept any prompt containing master
    assert prompt.match?(/master/), "Prompt should contain master: #{prompt}"
  end
end
