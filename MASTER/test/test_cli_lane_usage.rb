# frozen_string_literal: true

require_relative "test_helper"
require "tmpdir"
require "json"
require_relative "../lib/fix/run_budget"

# Every claude-cli call billed nothing, so the /fix heartbeat read "tokens = 0 (0)" for a whole run and
# RunBudget's spend caps never saw the lane. These hold the usage on its way into the ledger.
class TestCliLaneUsage < Minitest::Test
  Ledger = Struct.new(:costs) do
    def record_cost(amount, model:, tokens:, approximate: false)
      costs << { amount:, model:, tokens:, approximate: }
    end
  end

  OK = Struct.new(:success?).new(true)
  USAGE = { input_tokens: 9, cache_creation_input_tokens: 7179, cache_read_input_tokens: 100, output_tokens: 40 }.freeze

  def dispatcher(session, out)
    lane = Master::Review::LLMDispatcher.allocate
    lane.instance_variable_set(:@session, session)
    lane.instance_variable_set(:@bus, nil)
    lane.instance_variable_set(:@availability, Master::CLI::Routing::AvailabilityPolicy.new(config: {}))
    lane.define_singleton_method(:capture3_with_timeout) do |_timeout, *args, **|
      (@asked ||= []) << args
      [out, "", OK]
    end
    lane
  end

  def budget(root)
    Master::Fix::RunBudget.new(root:, max_passes: 1, env: {}, wall: -> { Time.at(0) }, out: ->(line) { line },
                               say: ->(text) { text }, poll_seconds: 0).start!
  end

  def test_a_claude_cli_call_reports_its_usage_to_the_run_budget_ledger
    Dir.mktmpdir do |root|
      reply = JSON.generate(type: "result", is_error: false, result: "ok", total_cost_usd: 0.014567, usage: USAGE)
      lane = dispatcher(Master::Trace::Session.new(root:), reply)
      run = budget(root)

      result = lane.send(:claude_cli_call, "claude-sonnet-5-5", [{ role: "user", content: "fix" }], nil)

      assert_equal "ok", result.value!
      assert_equal %w[--output-format json], lane.instance_variable_get(:@asked).last.last(2)
      assert_equal [0.014567, 7328], run.spend
    ensure
      run&.stop!
    end
  end

  # In json mode the limit arrives as an error result; it must still stand the lane down as a quota.
  def test_a_subscription_limit_in_a_json_result_is_still_a_quota
    reply = JSON.generate(type: "result", is_error: true, result: "You've hit your session limit - resets 4:30pm")
    lane = dispatcher(Ledger.new([]), reply)

    result = lane.send(:claude_cli_call, "claude-opus-5-5", [{ role: "user", content: "fix" }], nil)

    assert_equal :exhausted, result.category
  end

  # A CLI lane that reports no usage still counts: an estimate from the characters, marked approximate.
  def test_a_cli_lane_without_usage_bills_an_approximate_token_estimate
    ledger = Ledger.new([])
    lane = dispatcher(ledger, "x" * 400)
    lane.define_singleton_method(:find_agy_bin) { "/bin/agy" }

    result = lane.send(:send_agy_cli, "auto", [{ role: "user", content: "y" * 800 }], sys: nil)

    assert_predicate result, :ok?
    row = ledger.costs.last
    assert_operator row[:tokens], :>=, 300
    assert_in_delta 0.0, row[:amount]
    assert row[:approximate], "an estimate must say it is one"
  end
end
