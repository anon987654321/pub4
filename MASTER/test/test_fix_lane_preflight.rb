# frozen_string_literal: true

require_relative "test_helper"
require_relative "../lib/fix/lane_preflight"

class TestFixLanePreflight < Minitest::Test
  Preflight = Master::Fix::LanePreflight
  OPUS = "claude-cli:claude-opus-5-5"
  GEMMA = "ollama:gemma3:4b"

  class Agent
    def initialize(routes) = @routes = routes

    def model_for(operation:) = @routes.fetch(operation, OPUS)
  end

  def check(routes, live:, env: {})
    lines = []
    result = nil

    Master::Trace::Dmesg.stub(:status, ->(_unit, text, **) { lines << text }) do
      Master::Io::LaneSelection.stub(:live_lanes, live) do
        result = Preflight.check(agent: Agent.new(routes), env:)
      end
    end
    [result, lines]
  end

  def test_a_free_lane_for_a_tree_read_while_opus_is_live_refuses_the_run
    result, lines = check({ tree: GEMMA }, live: [OPUS, GEMMA])

    assert_kind_of Master::Result::Err, result
    assert_match(/tree would run on #{Regexp.escape(GEMMA)} \(local\) while #{OPUS} is live/, result.message)
    assert_includes lines, "structural_review -> #{OPUS} (remote)"
  end

  def test_every_operation_on_a_subscription_lane_starts
    result, lines = check({}, live: [OPUS])

    assert_nil result
    assert_equal Preflight::OPERATIONS.size, lines.size
  end

  def test_a_free_lane_is_accepted_when_nothing_better_is_live
    result, = check({ tree: GEMMA, file_write: GEMMA }, live: [GEMMA])

    assert_nil result
  end

  def test_the_operator_can_accept_a_free_lane
    result, = check({ tree: GEMMA }, live: [OPUS, GEMMA], env: { "MASTER_FIX_FREE_OK" => "1" })

    assert_nil result
  end
end
