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

  def test_startup_disk_abort_is_exposed_as_a_stopping_reason
    resource = Object.new
    resource.define_singleton_method(:measure) { { values: { disk_free_gb: 0.1 } } }
    resource.define_singleton_method(:disk_critical?) { |_measurement| true }

    run = Budget.new(
      root: @root,
      max_passes: 3,
      clock: -> { @now },
      wall: -> { Time.at(1000) },
      out: ->(line) { @lines << line },
      say: ->(line) { @said << line },
      poll_seconds: 0,
      resource_budget: resource,
      killer: ->(_reason) {},
    ).start!

    assert_match(/disk pressure at 0.1 GB free/, run.stopping)
    assert @said.any? { |line| line.include?("ABORT") }
  end

  # An abort ends the process with TERM before the pipeline can clean up, so it puts the autofix's
  # uncommitted bytes back itself; another writer's later save to a written file stays.
  def test_an_abort_puts_back_the_autofix_writes_before_it_kills
    Master::Fix::AutofixGuard.reset!
    ours, theirs = autofixed_pair
    killed = []

    killable(killed).abort_run!("protected path changed: test/x.rb", force: true)

    assert_equal ["A = 1\n", "B = 9\n"], [File.read(ours), File.read(theirs)]
    assert_equal 1, killed.size
  ensure
    Master::Fix::AutofixGuard.reset!
  end

  # The MASTER abort of 2026-10-23 left the model's half-applied edit to bin/loops in the tree. The
  # open pass goes back with the abort; a file another writer saved since is theirs and stays.
  def test_an_abort_rolls_back_the_open_pass_and_leaves_another_writers_file
    ours, theirs = pass_with_a_model_edit_and_a_foreign_save

    capture_io { killable([]).abort_run!("stalled, pass 1", force: true) }

    assert_equal ["X = 1\n", "X = 2\n"], [File.read(ours), File.read(theirs)]
  ensure
    Budget.hold_pass(nil)
  end

  # An open pass that wrote a.rb itself; b.rb was then saved by another writer.
  def pass_with_a_model_edit_and_a_foreign_save
    system("git", "-C", @root, "init", "-q")
    ours, theirs = %w[a.rb b.rb].map { |name| File.join(@root, name).tap { |path| File.write(path, "X = 1\n") } }
    committer = Master::Fix::FixLoop::Committer.new(git: Struct.new(:changed_paths).new([]), root: @root)
    committer.baseline!
    committer.begin_transaction!(Master::Fix::Transaction.new(root: @root, paths: %w[a.rb b.rb]))

    File.write(ours, "X = 1\n\ndef half_applied\n")
    committer.attest_written!(ours)
    File.write(theirs, "X = 2\n")
    [ours, theirs]
  end

  def killable(killed)
    Budget.new(root: @root, max_passes: 3, clock: -> { @now }, wall: -> { Time.at(1000) },
               out: ->(line) { @lines << line }, say: ->(line) { @said << line }, poll_seconds: 0,
               killer: ->(reason) { killed << reason })
  end

  # Two committed files the autofix rewrote; the second was then saved by someone else.
  def autofixed_pair
    system("git", "-C", @root, "init", "-q")
    paths = %w[a.rb b.rb].map { |name| File.join(@root, name) }
    paths.zip(["A = 1\n", "B = 1\n"]) { |path, body| File.write(path, body) }
    system("git", "-C", @root, "add", "a.rb", "b.rb")
    system("git", "-C", @root, "-c", "user.name=t", "-c", "user.email=t@t", "commit", "-qm", "base")

    paths.zip(["A = 1\n\n", "B = 1\n\n"]) do |path, body|
      before = File.read(path)
      File.write(path, body)
      Master::Fix::AutofixGuard.note_written(path, before:)
    end
    File.write(paths.last, "B = 9\n")
    paths
  end

  def test_stop_category_distinguishes_resource_failure_from_a_stall
    run = budget
    run.instance_variable_set(:@exit_reason, "disk pressure at 0.1 GB free")
    assert_equal :infrastructure, run.stop_category

    run.instance_variable_set(:@exit_reason, "disk space measurement unavailable; stopping before filesystem exhaustion")
    assert_equal :infrastructure, run.stop_category

    run.instance_variable_set(:@exit_reason, "stalled pass 2 phase scan")
    assert_equal :timeout, run.stop_category
  end

  def test_shared_run_does_not_enter_command_body_after_startup_abort
    reason = "disk pressure at 0.1 GB free; stopping before filesystem exhaustion"
    aborted = Object.new
    aborted.define_singleton_method(:stopping) { reason }
    aborted.define_singleton_method(:stop_category) { :infrastructure }
    aborted.define_singleton_method(:finish!) { |_why| true }
    body_ran = false

    starter = lambda do |**_kwargs|
      Budget.instance_variable_set(:@current, aborted)
      aborted
    end
    result = Budget.stub(:begin_run, starter) do
      Budget.with_shared_run(root: @root, max_passes: 3) do
        body_ran = true
        Master::Result.ok(:should_not_run)
      end
    end

    refute body_ran
    assert result.err?
    assert_equal :infrastructure, result.category
    assert_includes result.message, "disk pressure"
    assert_nil Budget.current
  ensure
    Budget.instance_variable_set(:@shared_depth, 0)
    Budget.instance_variable_set(:@shared_finishing, false)
    Budget.finish_run
    Master::Fix::RunLedger.reset!
  end

  def test_watchdog_survives_transient_beat_failures
    run = killable([])
    attempts = 0
    run.define_singleton_method(:beat) do
      attempts += 1
      raise "transient beat failure" if attempts <= 2

      instance_variable_set(:@exit_reason, "test complete")
    end

    capture_io { run.send(:watch) }

    assert_equal 3, attempts
    assert_equal "test complete", run.instance_variable_get(:@exit_reason)
  end

  def test_watchdog_stops_after_five_consecutive_failures
    run = killable([])
    attempts = 0
    run.define_singleton_method(:beat) do
      attempts += 1
      raise "persistent beat failure"
    end

    capture_io { run.send(:watch) }

    assert_equal Master::Fix::RunBudget::WATCHDOG_MAX_CONSECUTIVE_FAILURES, attempts
    assert_match(/watchdog failed 5 consecutive beats/, run.instance_variable_get(:@exit_reason))
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
    say.call("repair_loop:fix_applied", law: "X", file: "a.rb")
    say.call("repair_loop:fix_rejected", law: "X", file: "b.rb", reason: "lint")
    say.call("llm:send", model: "claude-cli:claude-opus-5-5")
    say.call("llm:provider_outcome", model: "claude-cli:claude-opus-5-5", status: "success")
    @now = 2412.0
    line = run.beat

    # forty minutes after its only finished file, the run is reported stalled and asked to stop
    stalled = "STALLED pass 2 phase scan for 40m, 0 files finished in 5m"
    stopping = "fix0: STOPPING stalled, pass 2 phase scan for 40m, 0 files finished in 5m; " \
               "ending the repair to prove what it did"

    assert_equal [line, "fix0: #{stalled}", stopping], @said
    assert_match(/\Afix0: pass 2\/8 scan0 phase scan files 812\/2638 \(31%\) run_pulse\.rb fixes 1 ok 1 failed /, line)
    assert_includes line, "lane claude-cli:claude-opus-5-5 last call 2412s ago"
    assert_includes line, "tokens = 342191 (342K) elapsed = 2412s (40m12s)"
    assert_match(/ eta (~\d+m|unknown) load \d+\.\d\z/, line)
    assert_operator line.length, :<, 215 # long lane ids, a six-digit token count and a named phase are the worst case
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
    say.call("repair_loop:pass", law: "A", violations: 7, fixed: 4, status: :continue)
    say.call("fix_loop:rule_result", pass: 1, rule: "B", violations: 3, fixed: 1)
    say.call("repair_loop:fix_applied", law: "A", file: "a.rb")
    say.call("fix_loop:skip_breakdown", pass: 1, declined: 2, fixed: 5)
    run.pass_end(1)

    assert_equal "fix0: pass 1 done, violations = 10 before 5 after", @said[0]
    assert_equal "fix0: pass 1 fixes = 1 ok 0 failed 2 skipped (declined 2)", @said[1]
    assert_match(/\Afix0: pass 1 commits = \d+ tokens = 5000 \(5K\)\z/, @said[2])
  end

  # Every gate is named at the pass boundary, a zero included, and the next pass counts afresh.
  def test_the_pass_summary_counts_refusals_by_gate
    run = budget
    Master::Fix::Refusals.begin_run!
    capture_io { Master::Fix::Refusals.record(gate: :scope, file: "a.rb", reason: "changes lines 90-91") }
    run.pass_end(1)
    run.pass_end(2)

    summaries = @said.grep(/\Afix0: refusals this pass: /)
    assert_includes summaries.first, " scope=1 "
    assert_includes summaries.first, " verifier=0 "
    assert_includes summaries.last, " scope=0 "
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

  def test_nested_fix_scopes_share_one_command_budget
    first_run = nil

    result = Budget.with_shared_run(root: @root, max_passes: 3) do
      first_run = Budget.current
      refute_nil first_run
      Master::Fix::RunLedger.reject("budget_scope_test", file: "sentinel.rb")

      nested_result = Budget.with_shared_run(root: @root, max_passes: 1) do
        assert_same first_run, Budget.current

        # FixLoop also calls begin_run. Inside the command scope that must not
        # reset the watchdog, ledger, or start time.
        Budget.begin_run(root: @root, max_passes: 99)
        assert_same first_run, Budget.current
        assert_equal({ "budget_scope_test" => 1 }, Master::Fix::RunLedger.reasons,
                     "nested begin_run must not reset command-level rejection accounting")

        # A nested caller cannot stop the budget owned by the command.
        Budget.finish_run(reason: "nested pass ended")
        assert_same first_run, Budget.current
        :nested_complete
      end

      assert_equal :nested_complete, nested_result
      assert_same first_run, Budget.current
      :command_complete
    end

    assert_equal :command_complete, result
    assert_nil Budget.current
    assert_equal 0, Budget.instance_variable_get(:@shared_depth)
  ensure
    Budget.finish_run
    Master::Fix::RunLedger.reset!
  end

  # One slow model call ended MASTER and OPENBSD runs: the stall watchdog fires after five minutes
  # with no file finished, and a call could outlast that. Inside a run every call ends sooner.
  def test_a_run_caps_every_model_call_under_the_stall_window
    clock = Master::Review::LLMDispatcher::PassClock
    window = Master::Fix::RunPulse::FINISH_WINDOW_SECONDS

    capture_io do
      Budget.with_shared_run(root: @root, max_passes: 1) do
        assert_operator clock.call_deadline(300), :<, window
        assert_equal 30, clock.call_deadline(30), "a tighter deadline of the caller's own stands"
      end
    end

    assert_equal 300, clock.call_deadline(300), "outside a run the dispatcher's own deadline stands"
  ensure
    Budget.finish_run
    Master::Fix::RunLedger.reset!
  end

  def test_shared_finish_guard_clears_even_if_finalization_raises
    original_finish = Budget.method(:finish_run)
    calls = 0
    failing_finish = lambda do |reason: "completed"|
      calls += 1
      raise "simulated finish failure" if calls == 2

      original_finish.call(reason:)
    end

    error = assert_raises(RuntimeError) do
      Budget.stub(:finish_run, failing_finish) do
        Budget.with_shared_run(root: @root, max_passes: 3) { :command_complete }
      end
    end

    assert_equal "simulated finish failure", error.message
    assert_equal false, Budget.instance_variable_get(:@shared_finishing)
    assert_equal 0, Budget.instance_variable_get(:@shared_depth)
  ensure
    Budget.finish_run
    Master::Fix::RunLedger.reset!
    Budget.instance_variable_set(:@shared_finishing, false)
    Budget.instance_variable_set(:@shared_depth, 0)
  end

  def test_shared_budget_is_finalized_when_a_nested_pass_raises
    started = nil

    error = assert_raises(RuntimeError) do
      Budget.with_shared_run(root: @root, max_passes: 3) do
        started = Budget.current
        Budget.with_shared_run(root: @root, max_passes: 1) do
          raise "simulated pass failure"
        end
      end
    end

    assert_equal "simulated pass failure", error.message
    refute_nil started
    assert_nil Budget.current
    assert_equal 0, Budget.instance_variable_get(:@shared_depth)
  ensure
    Budget.finish_run
  end

  def test_finish_run_clears_current_budget_if_final_reporting_raises
    run = budget
    Budget.instance_variable_set(:@current, run)
    run.instance_variable_set(:@say, ->(_text) { raise "simulated report failure" })

    error = assert_raises(RuntimeError) { Budget.finish_run }

    assert_equal "simulated report failure", error.message
    assert_nil Budget.current, "a stopped watchdog must not leave a dead run registered"
  ensure
    Budget.instance_variable_set(:@current, nil)
    Master::Fix::RunLedger.reset!
  end

  def test_pass_boundary_returns_a_timeout_result
    Master::Trace::Dmesg.with_verbosity("quiet") do
      Budget.begin_run(root: @root, max_passes: 3)
      assert_nil Budget.pass_boundary(1)
    end
  ensure
    Budget.finish_run
  end

  Rule = Struct.new(:id, :severity)

  # Every attempt writes a ledger row of 400 tokens at $0.00, as a subscription lane does.
  class BillingLoop < Master::Fix::RepairLoop
    attr_reader :asked

    def initialize(ledger:, **)
      super(**)
      @ledger = ledger
    end

    def fix_violation(_violation)
      @asked = @asked.to_i + 1
      File.open(@ledger, "a") { |f| f.puts(JSON.generate(ts: 1001, amount: 0.0, tokens: 400)) }
      :applied
    end
  end

  def test_a_law_over_its_share_is_skipped_once_and_counted
    run = budget({}, max_passes: 3)
    run.instance_variable_set(:@fix_budget, { "law_share" => 0.1, "run_tokens" => 2000, "law_shares" => { "BIG" => 0.5 } })
    Budget.instance_variable_set(:@current, run)
    ledger = File.join(@root, ".master", "costs.jsonl")
    make = ->(id) { BillingLoop.new(ledger:, law: Rule.new(id, :warning), agent: Object.new, scanner: Object.new, root: Master::ROOT) }
    file = File.join(@root, "a.rb")
    File.write(file, "x\n")
    violation = ->(n) { { file:, law: "TINY", message: "m#{n}", severity: :warning } }

    tiny = make.call("TINY")
    capture_io { 3.times { |n| tiny.send(:fix_batch, [violation.call(n)]) } }
    assert_equal 1, tiny.asked, "400 tokens against a 200-token share: one attempt, then skipped"
    assert_equal [{ skip_law_budget: 1 }], [tiny.instance_variable_get(:@batch_breakdown)]
    assert_equal 1, @lines.grep(/TINY not configured, law budget spent: \$0.00 and 400 tokens past 10%/).size

    big = make.call("BIG")
    capture_io { 3.times { |n| big.send(:fix_batch, [violation.call(n)]) } }
    assert_equal 3, big.asked, "the override gives BIG half the run's 2000 tokens"

    run.pass_end(1)
    assert_includes @said, "fix0: pass 1 1 laws over budget"
  ensure
    Budget.instance_variable_set(:@current, nil)
  end

  def test_dollars_trip_the_share_too
    run = budget({ "MASTER_FIX_MAX_COST" => "10" })
    run.note_law_cost("PRICEY", 0.5)
    refute run.law_limit_exceeded?("PRICEY")
    run.note_law_cost("PRICEY", 0.6)
    assert run.law_limit_exceeded?("PRICEY")
    refute run.law_limit_exceeded?("OTHER")
  end

  def test_with_no_run_nothing_is_ever_over
    refute Budget.law_limit_exceeded?("ANY")
    assert_equal [0.0, 0], Budget.run_spend
  end

  def test_spend_reads_only_what_was_appended
    run = budget
    cost(1.0, 10)
    assert_equal [1.0, 10], run.spend
    cost(2.0, 5)
    assert_equal [3.0, 15], run.spend
  end
end
