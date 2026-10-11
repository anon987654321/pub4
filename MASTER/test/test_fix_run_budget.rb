# frozen_string_literal: true

require "test_helper"
require "tmpdir"
require "json"
require_relative "../lib/fix/run_budget"

class TestFixRunBudget < Minitest::Test
  Budget = Master::Fix::RunBudget

  def setup
    @now = 0.0
    @lines = []
    @said = []
    @root = Dir.mktmpdir
    FileUtils.mkdir_p(File.join(@root, ".master"))
  end

  def teardown = FileUtils.remove_entry(@root)

  def budget(env = {}, max_passes: 10)
    Budget.new(root: @root, max_passes:, env:, clock: -> { @now }, wall: -> { Time.at(1000) },
               out: ->(line) { @lines << line }, say: ->(text) { @said << text }, poll_seconds: 0).start!
  end

  def cost(amount, tokens, ts: 1001)
    File.open(File.join(@root, ".master", "costs.jsonl"), "a") { |f| f.puts(JSON.generate(ts:, amount:, tokens:)) }
  end

  def test_boundary_line_carries_spend_tokens_stages_and_eta
    run = budget
    cost(0.5, 1200)
    cost(9.0, 99, ts: 10) # before this run
    run.note_output("scan0", "scanning")
    @now = 60.0
    run.note_output("fix0", "pass 1")
    @now = 120.0
    run.boundary(1)
    @now = 240.0
    run.boundary(3)

    assert_match(/spent \$0\.50 \/ \$50\.0, 1200 tokens/, @lines.first)
    assert_match(/scan0 60s/, @lines.first)
    assert_match(/ETA unknown/, @lines.first)
    assert_match(/ETA ~\d+m/, @lines[1])
  end

  def test_cost_limit_stops_with_a_named_reason
    run = budget({"MASTER_FIX_MAX_COST" => "1.0"})
    cost(1.5, 10)

    reason = run.boundary(2)

    assert_match(/MASTER_FIX_MAX_COST/, reason)
    assert_equal reason, @lines.last
  end

  def test_minutes_limit_stops
    run = budget({"MASTER_FIX_MAX_MINUTES" => "5"})
    @now = 400.0

    assert_match(/MASTER_FIX_MAX_MINUTES/, run.boundary(2))
  end

  def test_defaults_do_not_stop_and_zero_means_unlimited
    run = budget({"MASTER_FIX_MAX_COST" => "0"})
    cost(500, 1)

    assert_nil run.boundary(1)
    assert_match(/no limit/, @lines.first)
  end

  def test_nearing_a_limit_warns_once
    run = budget({"MASTER_FIX_MAX_COST" => "10"})
    cost(9, 1)
    run.boundary(1)
    run.boundary(2)

    assert_equal 1, @lines.count { |l| l.include?("past 80%") }
  end

  def test_a_silent_stage_is_reported_once
    run = budget
    run.note_output("scan0", "reading the corpus")
    @now = 119.0
    assert_nil run.check_stall
    @now = 130.0

    assert_equal "scan0: still working on reading the corpus, 130s without output", run.check_stall
    assert_nil run.check_stall
    assert_equal 1, @said.size
  end

  def test_pass_boundary_returns_a_timeout_result
    Budget.begin_run(root: @root, max_passes: 3)
    assert_nil Budget.pass_boundary(1)
  ensure
    Budget.finish_run
  end
end
