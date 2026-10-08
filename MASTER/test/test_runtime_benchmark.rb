# frozen_string_literal: true

require_relative "test_helper"

class TestRuntimeBenchmark < Minitest::Test
  def test_measure_is_deterministic_for_hash_key_order
    first = Master::Runtime::Benchmark.measure(label: "hash") { { b: 2, a: 1 } }
    second = Master::Runtime::Benchmark.measure(label: "hash") { { a: 1, b: 2 } }

    assert_equal first[:output_digest], second[:output_digest]
  end

  def test_compare_reports_output_change_and_regression
    before = { output_digest: "abc", wall_ms: 10.0 }
    after = { output_digest: "def", wall_ms: 12.0 }
    comparison = Master::Runtime::Benchmark.compare(before, after)

    refute comparison[:output_equal]
    assert comparison[:regression]
    assert_equal 1.2, comparison[:ratio]
  end
end
