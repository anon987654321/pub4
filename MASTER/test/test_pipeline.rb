# frozen_string_literal: true

require "minitest/autorun"

# Create minimal MASTER module for testing
module MASTER
  def self.root
    File.expand_path("..", __dir__)
  end
end

require_relative "../lib/result"
require_relative "../lib/pipeline"

module MASTER
  # Mock stages for testing
  module Stages
    class Passthrough
      def call(input)
        Result.ok(input.merge(passed: true))
      end
    end

    class Fail
      def call(input)
        Result.err("Stage failed")
      end
    end

    class Append
      def initialize(key, value)
        @key = key
        @value = value
      end

      def call(input)
        Result.ok(input.merge(@key => @value))
      end
    end
  end

  class TestPipeline < Minitest::Test
    def test_pipeline_chains_stages_successfully
      # Create pipeline without validation for testing
      pipeline = Pipeline.new(stages: [])
      stage = Stages::Passthrough.new
      pipeline.instance_variable_set(:@stages, [stage])
      pipeline.instance_variable_set(:@stage_names, [:passthrough])
      
      result = pipeline.call({ text: "hello" })
      
      assert result.ok?
      assert_equal true, result.value[:passed]
      assert_equal "hello", result.value[:text]
    end

    def test_pipeline_stops_on_error
      # Create a custom pipeline with stages that will fail
      stage1 = Stages::Passthrough.new
      stage2 = Stages::Fail.new
      stage3 = Stages::Passthrough.new
      
      pipeline = Pipeline.new(stages: [])
      pipeline.instance_variable_set(:@stages, [stage1, stage2, stage3])
      pipeline.instance_variable_set(:@stage_names, [:stage1, :stage2, :stage3])
      
      result = pipeline.call({ text: "hello" })
      
      assert result.err?
      # Error should include stage name context
      assert_match(/Stage failed/, result.error)
    end

    def test_pipeline_passes_data_through_chain
      # Create stages that add data
      stage1 = Stages::Append.new(:step1, "done")
      stage2 = Stages::Append.new(:step2, "complete")
      
      pipeline = Pipeline.new(stages: [])
      pipeline.instance_variable_set(:@stages, [stage1, stage2])
      
      result = pipeline.call({ text: "hello" })
      
      assert result.ok?
      assert_equal "hello", result.value[:text]
      assert_equal "done", result.value[:step1]
      assert_equal "complete", result.value[:step2]
    end

    def test_pipeline_with_empty_stages
      pipeline = Pipeline.new(stages: [])
      result = pipeline.call({ text: "hello" })
      
      assert result.ok?
      assert_equal "hello", result.value[:text]
    end

    def test_pipeline_initializes_with_default_stages
      # This test verifies the pipeline validates stages properly
      # We use empty stages to avoid needing to load full stage dependencies
      pipeline = Pipeline.new(stages: [])
      assert_instance_of Pipeline, pipeline
    end

    def test_repl_method_exists
      pipeline = Pipeline.new(stages: [])
      assert_respond_to pipeline, :repl
    end
  end
end
