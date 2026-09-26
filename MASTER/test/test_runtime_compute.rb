# frozen_string_literal: true

require_relative "test_helper"

module Master
  class RuntimeComputeTestStage
    def initialize(multiplier)
      @multiplier = multiplier
    end

    def ractor_safe? = true

    def ractor_payload(ctx)
      { "message" => ctx[:user_message], "multiplier" => @multiplier }
    end

    def self.ractor_call(payload)
      { "ractor_#{payload.fetch("message")}_#{payload.fetch("multiplier")}" => payload.fetch("multiplier") }
    end
  end
end

class TestRuntimeCompute < Minitest::Test
  def test_serial_backend_preserves_order
    result = Master::Runtime::Compute.map([1, 2, 3], backend: :serial) { |value, index| value + index }

    assert_equal [1, 3, 5], result
  end

  def test_thread_backend_preserves_order
    result = Master::Runtime::Compute.map((0...16).to_a, backend: :thread) { |value, _index| value * 2 }

    assert_equal (0...16).map { |value| value * 2 }, result
  end

  def test_auto_selects_ractor_for_an_explicit_invoke_protocol
    skip "Ractors unavailable" unless Master::Runtime::Compute.ractor_available?

    jobs = 4.times.map do |value|
      ["Master::RuntimeComputeTestStage", "ractor_call", { "message" => value.to_s, "multiplier" => value + 1 }]
    end

    result = Master::Runtime::Compute.map(jobs, backend: :auto, operation: :invoke)

    assert_equal 4, result.size
    assert_equal({ "ractor_3_4" => 4 }, result[3])
  end

  def test_parallel_group_uses_ractors_for_ractor_safe_stages
    skip "Ractors unavailable" unless Master::Runtime::Compute.ractor_available?

    group = Master::CLI::Pipeline::ParallelGroup.new(
      Master::RuntimeComputeTestStage.new(2),
      Master::RuntimeComputeTestStage.new(3),
    )

    result = group.call(user_message: "hello")

    assert result.ok?, result.inspect
    assert_equal({ user_message: "hello", "ractor_hello" => 2 }, result.value!)
  end

  def test_parallel_group_can_force_the_thread_backend
    group = Master::CLI::Pipeline::ParallelGroup.new(
      Master::RuntimeComputeTestStage.new(2),
      Master::RuntimeComputeTestStage.new(3),
      backend: :thread,
    )

    result = group.call(user_message: "hello")

    refute result.ok?, "Ractor-only stages should not silently execute as Thread stages"
    assert_match(/undefined method|ractor|call/, result.message)
  end
end
