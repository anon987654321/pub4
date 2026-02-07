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
require_relative "../lib/dmesg"

module MASTER
  class TestHardening < Minitest::Test
    # Test 1: Result type safety
    def test_result_ok_with_nil_is_unambiguous
      result = Result.ok(nil)
      assert result.ok?
      refute result.err?
      assert_equal :ok, result.kind
    end

    def test_result_kind_field
      assert_equal :ok, Result.ok(1).kind
      assert_equal :err, Result.err("fail").kind
    end

    def test_result_values_frozen
      result = Result.ok("mutable")
      assert result.value.frozen?
      
      err = Result.err("error")
      assert err.error.frozen?
    end

    # Test 2: StandardError rescue in Result
    def test_result_map_rescues_standard_error
      result = Result.ok(1).map { raise StandardError, "boom" }
      assert result.err?
      assert_equal "boom", result.error
    end

    def test_result_flat_map_rescues_standard_error
      result = Result.ok(1).flat_map { raise StandardError, "boom" }
      assert result.err?
      assert_equal "boom", result.error
    end

    # Test 8: Stage name validation
    def test_pipeline_validates_stage_names
      error = assert_raises(ArgumentError) do
        Pipeline.new(stages: [:invalid_stage])
      end
      assert_match(/Invalid stage/, error.message)
      assert_match(/valid stages/i, error.message)
    end

    # Test 11: Stage name in error context - tested in integration
    # Requires full stage setup with LLM, DB, etc.

    # Test 12: Buffer capping
    def test_dmesg_buffer_capped
      Dmesg.clear
      
      # Add more than MAX_BUFFER_SIZE entries
      (Dmesg::MAX_BUFFER_SIZE + 100).times do |i|
        Dmesg.log("test#{i}", message: "test")
      end
      
      assert_operator Dmesg.buffer.size, :<=, Dmesg::MAX_BUFFER_SIZE
    end
  end
end
