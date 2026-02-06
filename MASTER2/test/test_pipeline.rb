# frozen_string_literal: true

require "minitest/autorun"
require_relative "../lib/master"

class TestPipeline < Minitest::Test
  def setup
    # Use in-memory database for tests
    MASTER::DB.setup(path: ":memory:")
  end

  def test_pipeline_initialization
    pipeline = MASTER::Pipeline.new
    assert_equal 4, pipeline.stages.length
  end

  def test_stage_class_conversion
    pipeline = MASTER::Pipeline.new
    klass = pipeline.stage_class(:input_tank)
    assert_equal MASTER::Stages::InputTank, klass
  end

  def test_pipeline_call_with_string
    pipeline = MASTER::Pipeline.new
    result = pipeline.call("test input")
    assert result.ok?, "Pipeline should succeed with string input"
  end

  def test_pipeline_call_with_hash
    pipeline = MASTER::Pipeline.new
    result = pipeline.call({ text: "test input" })
    assert result.ok?, "Pipeline should succeed with hash input"
  end

  def test_pipeline_preserves_data
    pipeline = MASTER::Pipeline.new
    result = pipeline.call({ text: "test", custom: "data" })
    assert result.ok?
    assert result.value[:custom] == "data", "Custom data should be preserved"
  end

  def test_pipeline_short_circuits_on_error
    # Create a custom stage that fails
    failing_stage = Class.new do
      def call(input)
        MASTER::Result.err("intentional failure")
      end
    end

    # Monkey patch stages temporarily
    original_stages = MASTER::Pipeline::DEFAULT_STAGES
    MASTER::Pipeline.const_set(:DEFAULT_STAGES, [:input_tank])
    
    pipeline = MASTER::Pipeline.new(stages: [failing_stage.new])
    result = pipeline.call({ text: "test" })
    
    assert result.err?
    assert_equal "intentional failure", result.error
  ensure
    MASTER::Pipeline.const_set(:DEFAULT_STAGES, original_stages)
  end
end
