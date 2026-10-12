# frozen_string_literal: true

require_relative "test_helper"

class TestModelHealth < Minitest::Test
  Registry = Master::CLI::CommandRegistry

  Pool = Struct.new(:stats) do
    def snapshot = stats
  end

  Router = Struct.new(:compute_pool) do
    def unreachable_reason(*) = nil
  end

  Agent = Struct.new(:model_router)

  def report(stats)
    Registry.model_health(agent: Agent.new(Router.new(Pool.new(stats))))
  end

  def test_health_report_summarizes_success_failure_and_latency
    result = report(
      "local:small" => { calls: 4, successes: 4, failures: 0, latency_ms: 850.0 },
      "gateway:unstable" => {
        calls: 5, successes: 2, failures: 3, latency_ms: 1_200.0,
        last_error: "Authorization: Bearer must-never-be-rendered",
      },
    )

    assert_includes result, "model health: 2 models, 9 calls, success=66.7%, failures=3"
    assert_includes result, "gateway:unstable  calls=5 ok=2 fail=3 success=40.0% avg=1200ms"
    assert_includes result, "local:small  calls=4 ok=4 fail=0 success=100.0% avg=850ms"
    refute_includes result, "must-never-be-rendered"
  end

  def test_model_health_is_reachable_through_the_model_subcommand
    result = Registry.dispatch_model(
      agent: Agent.new(Router.new(Pool.new(
        "provider:model" => { calls: 2, successes: 1, failures: 1, latency_ms: 400.0 },
      ))),
      config: nil,
      metrics: nil,
      root: Master::ROOT,
      arg: "health",
    )

    assert_includes result, "model health: 1 models, 2 calls, success=50.0%, failures=1"
  end

  def test_health_report_states_when_no_calls_have_been_recorded
    assert_equal(
      "model health: no recorded calls yet; /model compute lists reachable lanes",
      report("untried" => { calls: 0, successes: 0, failures: 0, latency_ms: 0.0 }),
    )
  end

  def test_health_report_caps_the_number_of_model_rows
    stats = 35.times.to_h do |index|
      ["provider:model-#{index}", { calls: 1, successes: 1, failures: 0, latency_ms: 100.0 }]
    end

    result = report(stats)

    assert_includes result, "... 5 more models"
    assert_equal 32, result.lines.size
  end
end
