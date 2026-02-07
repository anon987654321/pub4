# frozen_string_literal: true

require "minitest/autorun"
require_relative "../lib/master"

class TestPipeline < Minitest::Test
  include Dry::Monads[:result]

  def setup
    # Use in-memory database for tests
    MASTER::DB.setup(path: ":memory:")
  end

  def test_pipeline_initialization
    pipeline = MASTER::Pipeline.new
    assert_equal 7, pipeline.stages.length
  end

  def test_stage_class_conversion
    pipeline = MASTER::Pipeline.new
    klass = pipeline.stage_class(:compress)
    assert_equal MASTER::Stages::Compress, klass
  end

  def test_pipeline_call_with_string
    # Use pipeline without Ask stage (requires API keys)
    pipeline = MASTER::Pipeline.new(stages: %i[input_tank guard council_debate refactor_engine openbsd_admin output_tank])
    result = pipeline.call("test input")
    assert result.success?, "Pipeline should succeed with string input"
  end

  def test_pipeline_call_with_hash
    # Use pipeline without Ask stage (requires API keys)
    pipeline = MASTER::Pipeline.new(stages: %i[input_tank guard council_debate refactor_engine openbsd_admin output_tank])
    result = pipeline.call({ text: "test input" })
    assert result.success?, "Pipeline should succeed with hash input"
  end

  def test_pipeline_preserves_data
    # Use pipeline without Ask stage (requires API keys)
    pipeline = MASTER::Pipeline.new(stages: %i[input_tank guard council_debate refactor_engine openbsd_admin output_tank])
    result = pipeline.call({ text: "test", custom: "data" })
    assert result.success?
    assert result.value![:custom] == "data", "Custom data should be preserved"
  end

  def test_pipeline_short_circuits_on_error
    # Create a custom stage that fails
    failing_stage = Class.new do
      include Dry::Monads[:result]
      
      def call(_input)
        Failure("intentional failure")
      end
    end

    # Monkey patch stages temporarily
    original_stages = MASTER::Pipeline::DEFAULT_STAGES
    MASTER::Pipeline.const_set(:DEFAULT_STAGES, [:compress])

    pipeline = MASTER::Pipeline.new(stages: [failing_stage.new])
    result = pipeline.call({ text: "test" })

    assert result.failure?
    assert_equal "intentional failure", result.failure
  ensure
    MASTER::Pipeline.const_set(:DEFAULT_STAGES, original_stages)
  end

  def test_build_prompt_with_budget
    prompt = MASTER::Pipeline.prompt
    assert_match(/^master\[/, prompt, "Prompt should start with 'master['")
    assert_match(/\|\$\d+\.\d{2}\]> $/, prompt, "Prompt should end with budget format '|$X.XX]> '")
  end

  def test_build_prompt_shows_tier
    prompt = MASTER::Pipeline.prompt
    # Should contain one of the tiers or "none"
    assert_match(/\[(strong|fast|cheap|none)/, prompt, "Prompt should contain a tier")
  end

  def test_build_prompt_format
    prompt = MASTER::Pipeline.prompt
    # Full format: master[tier|$budget]> 
    # Or with circuit: master[tier⚡|$budget]> 
    assert_match(/^master\[(strong|fast|cheap|none)(⚡)?\|\$\d+\.\d{2}\]> $/, prompt, "Prompt should match expected format")
  end
end
