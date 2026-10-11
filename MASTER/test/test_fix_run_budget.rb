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

  def pulse_bus
    bus = Master::Trace::EventBus.new(event_log: Struct.new(:x) { def append(*) = nil }.new(0))
    [bus, ->(event, **payload) { bus.publish(event, payload) }]
  end

  def test_heartbeat_never_leaves_a_gap_over_thirty_seconds
    run = budget
    run.note_output("scan0", "reading the corpus")
    beats = []
    (1..300).each do |second|
      @now = second.to_f
      beats << second if run.beat
    end

    assert_equal [28, 56, 84, 112, 140, 168, 196, 224, 252, 280], beats
    assert_operator (beats + [300]).each_cons(2).map { |a, b| b - a }.max, :<, 30
    assert_equal 10, @said.size
  end

  def test_heartbeat_carries_phase_files_fixes_lane_tokens_elapsed_and_load
    run = budget(max_passes: 8)
    bus, say = pulse_bus
    run.announce(target: "MASTER", bus:)
    @said.clear
    cost(0.5, 342_191)
    run.note_output("scan0", "scanning")
    run.boundary(2)
    say.call("fix_loop:pass_start", pass: 2, target: "MASTER", file_count: 2638)
    say.call("scan:progress", done: 812, total: 2638, path: "lib/fix/run_pulse.rb", violations: 1)
    say.call("law_loop:fix_applied", law: "X", file: "a.rb")
    say.call("law_loop:fix_rejected", law: "X", file: "b.rb", reason: "lint")
    say.call("llm:send", model: "claude-cli:claude-opus-5-5")
    say.call("llm:provider_outcome", model: "claude-cli:claude-opus-5-5", status: "success")
    @now = 2412.0
    line = run.beat

    assert_equal [line], @said
    assert_match(/\Afix0: pass 2\/8 scan0 files 812\/2638 \(31%\) run_pulse\.rb fixes 1 ok 1 failed /, line)
    assert_includes line, "lane claude-cli:claude-opus-5-5 last call 2412s ago"
    assert_includes line, "tokens = 342191 (342K) elapsed = 2412s (40m12s)"
    assert_match(/ eta (~\d+m|unknown) load \d+\.\d\z/, line)
    assert_operator line.length, :<, 195 # long lane ids and a six-digit token count are the worst case
  end

  def test_a_blocked_model_call_names_its_lane_and_the_wait
    run = budget
    bus, say = pulse_bus
    run.announce(target: "MASTER", bus:)
    @said.clear
    @now = 10.0
    say.call("llm:send", model: "agy:gemini-3")
    @now = 38.0
    assert_includes run.beat, "waiting on agy:gemini-3 for 28s"
    @now = 66.0
    assert_includes run.beat, "waiting on agy:gemini-3 for 56s"
    say.call("llm:provider_outcome", model: "agy:gemini-3", status: "success")
    @now = 94.0
    refute_match(/waiting on/, run.beat)
  end

  def test_pass_summary_block_counts_before_after_fixes_skips_and_commits
    run = budget
    bus, say = pulse_bus
    run.announce(target: "MASTER", bus:)
    @said.clear
    cost(0.1, 5000)
    say.call("fix_loop:pass_start", pass: 1, target: "MASTER", file_count: 3)
    say.call("law_loop:pass", law: "A", violations: 7, fixed: 4, status: :continue)
    say.call("fix_loop:rule_result", pass: 1, rule: "B", violations: 3, fixed: 1)
    say.call("law_loop:fix_applied", law: "A", file: "a.rb")
    say.call("fix_loop:skip_breakdown", pass: 1, declined: 2, fixed: 5)
    run.pass_end(1)

    assert_equal "fix0: pass 1 done, violations = 10 before 5 after", @said[0]
    assert_equal "fix0: pass 1 fixes = 1 ok 0 failed 2 skipped (declined 2)", @said[1]
    assert_match(/\Afix0: pass 1 commits = \d+ tokens = 5000 \(5K\)\z/, @said[2])
  end

  def test_banner_is_dmesg_shaped_with_not_configured_lines
    lines = Master::Fix::RunPulse::Banner.lines(
      root: "/r/MASTER", target: "RAILS", max_passes: 8, limits: "budget $50.0 / 480m", now: Time.at(0).utc,
      probes: { sha: "abc1234", mem: 17_179_869_184,
                states: ["claude-cli: live", "agy: quota spent, back in 140h44m (2026-10-17 04:12)"],
                ports: { "amber" => false, "bsdports" => true } }
    )

    assert_match(/\AMASTER \S+ \(FIX\) #abc1234: /, lines[0])
    assert_match(/\A    \S+@\S+:\/r\/MASTER\z/, lines[1])
    assert_equal "real mem = 17179869184 (16384MB)", lines[2]
    assert_includes lines, "lane0 at fix0: claude-cli"
    assert_includes lines, "agy at fix0: not configured, quota spent, back in 140h44m (2026-10-17 04:12)"
    assert_includes lines, "amber0 at triangle0: not configured, port 61352 not answering"
    refute(lines.any? { |l| l.start_with?("bsdports0") })
    assert(lines.none? { |l| l.start_with?(" ") && !l.start_with?("    ") })
  end

  def test_pass_boundary_returns_a_timeout_result
    Master::Trace::Dmesg.with_verbosity("quiet") do
      Budget.begin_run(root: @root, max_passes: 3)
      assert_nil Budget.pass_boundary(1)
    end
  ensure
    Budget.finish_run
  end
end
