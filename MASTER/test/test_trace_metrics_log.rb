# frozen_string_literal: true

require_relative "test_helper"
require "json"
require "tmpdir"

class TraceMetricsLogTest < Minitest::Test
  def test_metrics_log_is_bounded_private_jsonl
    Dir.mktmpdir("trace-metrics-") do |root|
      metrics = Master::Trace::Metrics.new(root:)
      metrics.record_model_benchmark(
        model: "provider-a",
        tasks: 2,
        passed: 1,
        failed: 1,
        success_rate: 0.5,
        elapsed_ms: 240,
        avg_ms: 120,
        errors: ["one timeout"],
      )

      path = File.join(root, ".master", "metrics.jsonl")
      assert File.file?(path)
      record = JSON.parse(File.readlines(path).last)
      assert_equal "provider-a", record.fetch("model_benchmark").fetch("model")
      assert_equal 0o600, File.stat(path).mode & 0o777
      assert_equal 0o700, File.stat(File.dirname(path)).mode & 0o777
      assert File.file?("#{path}.lock")
    end
  end
end
