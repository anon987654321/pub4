# frozen_string_literal: true

require "test_helper"
require "tmpdir"
require_relative "../lib/fix/run_budget"
require_relative "../lib/operator/stall_watch"

# The watchdog and heartbeat of /fix. The 2026-10-12 run failed a file every few
# minutes for an hour and the old watchdog, which only watched for zero files
# attempted, never spoke; the operator's filter also missed the `fix0 phase`
# lines. Driven with a fake clock and a fake killer: nothing is signalled.
class TestFixWatchdog < Minitest::Test
  Pulse = Master::Fix::RunPulse
  Budget = Master::Fix::RunBudget

  def setup
    @now = 0.0
    @said = []
    @killed = []
    @root = Dir.mktmpdir
    @env = %w[MASTER_FIX_NOYIELD_S MASTER_FIX_NOYIELD_ATTEMPTS MASTER_FIX_ABORT_ON_STALL].to_h { |k| [k, ENV.delete(k)] }
    Master::Fix::AutofixGuard.reset!
    Master::Fix::RunLedger.reset!
  end

  def teardown
    FileUtils.remove_entry(@root)
    @env.each { |k, v| v ? ENV[k] = v : ENV.delete(k) }
  end

  def pulse
    Pulse.new(max_passes: 8, clock: -> { @now }, load: -> { 0.0 }).tap { |p| p.observe("fix_loop:pass_start", pass: 1, file_count: 100) }
  end

  # A grace of 0 kills on a stall at once, as these tests assert; the graceful stop has its own test.
  def budget(resource_budget: nil, grace: "0")
    resource_budget ||= fake_resource_budget(free_gb: 100.0)
    env = { "MASTER_FIX_STOP_GRACE_S" => grace }
    Budget.new(root: @root, max_passes: 8, env:, clock: -> { @now }, wall: -> { Time.at(1000) },
               out: ->(_) {}, say: ->(text) { @said << text }, poll_seconds: 0,
               killer: ->(reason) { @killed << reason }, resource_budget:).start!
  end

  def test_a_stall_with_grace_stops_the_run_for_its_proof_before_any_kill
    run = budget(grace: "600")
    bus = Master::Trace::EventBus.new
    run.announce(target: @root, bus:)
    bus.publish("fix_loop:pass_start", pass: 1, file_count: 100)
    bus.publish("fix_loop:phase", stage: :stream)
    @now = Master::Fix::FixTime.stall_s + 1

    run.watch_for_stall

    assert_match(/stalled, pass 1/, run.stopping)
    assert_empty @killed, "a run asked to stop is not killed before its grace"
    assert(@said.any? { |line| line.start_with?("fix0: STOPPING") })
  end

  def fake_resource_budget(free_gb:)
    state = { free_gb: }
    probe = Object.new
    probe.define_singleton_method(:measure) do
      { state: :ok, reasons: [], values: { disk_free_gb: state[:free_gb] } }
    end
    probe.define_singleton_method(:free_gb=) { |value| state[:free_gb] = value }
    probe.define_singleton_method(:disk_critical?) do |reading|
      free = reading.dig(:values, :disk_free_gb)
      free.nil? || free <= 2.0
    end
    probe
  end

  # A run that keeps attempting and never fixes: files keep finishing, so the pass-stall rule
  # (nothing finished in five minutes) stays quiet, and the no-yield rule ends it at twenty.
  def test_no_fix_after_twenty_minutes_of_attempts_is_a_stall_that_aborts
    p = pulse
    20.times do |i|
      @now = 60.0 * (i + 1)
      p.observe("repair_loop:proposal_rejected", reason: "new_violations")
    end

    @now = 1199.0
    refute p.stall(@now)&.fetch(:abort, nil), "under twenty minutes it only reports"

    @now = 1261.0
    stalled = p.stall(@now)
    assert_equal "fix0: STALLED no yield: 0 fixed after 20m, 20 attempts", stalled[:line]
    assert stalled[:abort]
  end

  def test_a_fix_or_too_few_attempts_is_not_a_no_yield_stall
    p = pulse
    4.times { p.observe("repair_loop:proposal_rejected", reason: "x") }
    @now = 3000.0
    p.observe("repair_loop:file_timeout", file: "a.rb")
    p.observe("repair_loop:proposal_rejected", reason: "x")
    p.observe("repair_loop:fix_applied", file: "a.rb")
    refute p.stall(@now)&.fetch(:abort, nil)
  end

  def test_the_thresholds_are_configurable
    ENV["MASTER_FIX_NOYIELD_S"] = "60"
    ENV["MASTER_FIX_NOYIELD_ATTEMPTS"] = "2"
    p = pulse
    2.times { p.observe("repair_loop:proposal_rejected", reason: "x") }
    @now = 61.0

    assert_match(/no yield: 0 fixed after 1m, 2 attempts/, p.stall(@now)[:line])
  end

  def test_a_non_advisory_pass_with_no_files_attempted_aborts_at_the_stall_limit
    p = pulse
    p.observe("fix_loop:phase", stage: :stream)
    @now = Master::Fix::FixTime.stall_s + 1

    stalled = p.stall(@now)

    assert_match(/STALLED pass 1 phase scan \+ stream fixes for 10m, 0 files attempted/, stalled[:line])
    refute stalled[:skippable]
    assert stalled[:abort], "direct CLI runs must not rely on the outer wrapper watchdog"
  end

  # A four-tree /fix shares one pulse. OPENBSD's pass crashed mid-call on 2026-10-26, and its
  # pass, phase and unanswered call kept reading as a stall until the watchdog stopped STUDIO.
  def test_a_tree_that_ended_leaves_no_pass_or_call_to_stall_the_next
    p = pulse
    p.observe("fix_loop:phase", stage: :stream)
    p.observe("llm:send", model: "claude-cli:claude-sonnet-5-5")
    p.observe("fix_loop:terminal", state: :crash, target: "OPENBSD")
    @now = Master::Fix::FixTime.stall_s * 2

    assert_nil p.stall(@now)
    refute_match(/waiting on/, p.line(elapsed: @now, tokens: 0, eta: nil))
  end

  def test_a_scan_that_keeps_finishing_files_is_not_a_stall_even_with_no_repair_yet
    p = pulse
    p.observe("fix_loop:phase", stage: :stream)
    @now = Master::Fix::FixTime.stall_s + 1
    p.observe("scan:complete", path: "app/models/post.rb", count: 0)
    @now += 60

    assert_nil p.stall(@now), "one clean file a minute is a slow semantic scan, not a hang"
  end

  # The pass's budgeted semantic reads follow its first repairs. Opus took two minutes a file,
  # and the third MASTER run of 2026-10-27 was cut as "0 files finished in 5m" mid-read.
  def test_a_scan_still_finishing_files_after_the_first_repairs_is_not_a_stall
    p = pulse
    p.observe("fix_loop:phase", stage: :stream)
    p.observe("repair_loop:proposal_rejected", reason: "reflexion_unsafe")
    @now = Master::Fix::FixTime.stall_s + 1
    p.observe("scan:complete", path: "law/lexical.rb", count: 3)
    @now += 60

    assert_nil p.stall(@now)
  end

  # Opus needs minutes a call, so a run gives each file 900 s; a five-minute finish window
  # would cut a repair still inside its own budget.
  def test_the_finish_window_is_never_shorter_than_a_files_budget
    ENV["MASTER_FIX_FILE_BUDGET_S"] = "900"
    p = pulse
    p.observe("fix_loop:phase", stage: :stream)
    @now = Master::Fix::FixTime.stall_s + 1
    p.observe("repair_loop:proposal_rejected", reason: "reflexion_unsafe")

    assert_nil p.stall(@now + 600), "ten minutes into a fifteen-minute file is not a stall"
    assert_match(/0 files finished in 16m/, p.stall(@now + 1000)[:line])
  ensure
    ENV.delete("MASTER_FIX_FILE_BUDGET_S")
  end

  def test_a_scan_that_stopped_finishing_files_stalls_again
    p = pulse
    p.observe("fix_loop:phase", stage: :stream)
    @now = Master::Fix::FixTime.stall_s + 1
    p.observe("scan:complete", path: "app/models/post.rb", count: 0)
    @now += Pulse::FINISH_WINDOW_SECONDS + 1

    assert_match(/0 files attempted/, p.stall(@now)[:line])
  end

  def test_an_advisory_pass_stall_is_skipped_instead_of_aborting_the_run
    p = pulse
    p.observe("fix_loop:phase", stage: :council)
    @now = Master::Fix::FixTime.stall_s + 1

    stalled = p.stall(@now)

    assert stalled[:skippable]
    refute stalled[:abort]
  end

  def test_report_only_mode_cannot_disable_the_non_advisory_stall_safety_stop
    ENV["MASTER_FIX_ABORT_ON_STALL"] = "0"
    run = budget
    p = pulse
    p.observe("fix_loop:phase", stage: :stream)
    run.instance_variable_set(:@pulse, p)
    @now = Master::Fix::FixTime.stall_s + 1

    run.send(:watch_for_stall)

    assert_equal 1, @killed.size
    assert_match(/stalled, pass 1/, @killed.first)
    assert(@said.any? { |line| line.start_with?("fix0: run ended reason=stalled") })
    refute(@said.any? { |line| line.start_with?("fix0: STALL REPORT ONLY") })
  end

  def test_stream_stall_is_reported_and_terminates_the_run
    run = budget
    p = pulse
    p.observe("fix_loop:phase", stage: :stream)
    run.instance_variable_set(:@pulse, p)
    @now = Master::Fix::FixTime.stall_s + 1

    run.send(:watch_for_stall)

    assert_equal 1, @killed.size
    assert_match(/phase scan \+ stream fixes/, @killed.first)
    assert(@said.any? { |line| line.include?("0 files attempted") })
  end

  def test_advisory_stall_cancels_the_council_without_terminating_the_run
    run = budget
    p = pulse
    p.observe("fix_loop:phase", stage: :council)
    run.instance_variable_set(:@pulse, p)
    @now = Master::Fix::FixTime.stall_s + 1

    run.send(:watch_for_stall)

    assert_empty @killed
    assert Master::Review::LLMDispatcher::PassClock.cancelled?
    assert(@said.any? { |line| line.include?("STALLED pass 1 phase council") })
  ensure
    Master::Review::LLMDispatcher::PassClock.reset_cancel!
  end

  def test_stop_does_not_kill_the_current_watchdog_before_a_safety_abort_finishes
    run = budget
    run.instance_variable_set(:@watchdog, Thread.current)

    run.stop!

    assert Thread.current.alive?, "stop! killed the thread that still had to finish the abort"
    assert_nil run.instance_variable_get(:@watchdog)
  end

  def test_the_machine_heartbeat_has_the_documented_shape
    p = pulse
    p.observe("fix_loop:phase", stage: :stream)
    p.observe("repair_loop:fix_applied", {})
    2.times { p.observe("repair_loop:proposal_rejected", reason: "x") }
    p.observe("repair_loop:fix_error", {})
    p.observe("llm:send", model: "grok-cli:auto")

    assert_equal "fix0 phase=stream fixed=1 failed=1 rejected=2 lane=grok-cli:auto elapsed=61", p.machine_line(61.4)
  end

  def test_the_machine_heartbeat_comes_once_a_minute
    run = budget
    run.instance_variable_set(:@pulse, pulse)
    @now = 30.0
    run.send(:machine_beat, @now)
    assert_empty @said
    @now = 61.0
    run.send(:machine_beat, @now)
    @now = 90.0
    run.send(:machine_beat, @now)

    assert_equal 1, @said.size
    assert_match(/\Afix0 phase=scan fixed=0 failed=0 rejected=0 lane=none elapsed=61\z/, @said.first)
  end

  def test_disk_pressure_is_checked_before_the_watchdog_or_work_starts
    run = budget(resource_budget: fake_resource_budget(free_gb: 1.25))

    assert_equal 1, @killed.size
    assert_match(/disk pressure at 1.25 GB free/, @killed.first)
    assert(run.instance_variable_get(:@finished_said), "preflight must emit the terminal report")
    assert(@said.any? { |line| line.include?("stopping before filesystem exhaustion") })

    before_announce = @said.size
    bus = Object.new
    bus.define_singleton_method(:subscribe) { |*| raise "an aborted run must not attach listeners" }
    run.announce(target: @root, bus:)
    assert_equal before_announce, @said.size, "an aborted preflight must not announce a new run"
  end

  def test_disk_pressure_aborts_before_filesystem_exhaustion
    resource_budget = fake_resource_budget(free_gb: 100.0)
    run = budget(resource_budget:)
    resource_budget.free_gb = 1.25
    ENV["MASTER_FIX_ABORT_ON_STALL"] = "0"
    @now = Budget::RESOURCE_CHECK_SECONDS + 1

    run.send(:guard_check, @now)

    assert_equal 1, @killed.size
    assert_match(/disk pressure at 1.25 GB free/, @killed.first)
    assert(@said.any? { |line| line.include?("stopping before filesystem exhaustion") })
  end

  def test_a_no_yield_stall_ends_the_run_with_a_summary_naming_the_reason
    run = budget
    p = pulse
    5.times { p.observe("repair_loop:proposal_rejected", reason: "new_violations") }
    run.instance_variable_set(:@pulse, p)
    @now = 1300.0

    run.send(:watch_for_stall)

    assert_equal 1, @killed.size
    assert_match(/no yield/, @killed.first)
    assert(@said.any? { |line| line.start_with?("fix0: run ended reason=stalled, no yield") })
    assert(@said.any? { |line| line.include?("self-check") })
  end

  def test_hard_safety_abort_supersedes_a_report_only_stall
    ENV["MASTER_FIX_ABORT_ON_STALL"] = "0"
    run = budget
    run.send(:abort_run!, "stalled, test")

    run.send(:abort_run!, "disk pressure", force: true)

    assert_equal ["disk pressure"], @killed
    assert(@said.any? { |line| line == "fix0: ABORT disk pressure" })
  end

  def test_abort_can_be_turned_into_a_report
    ENV["MASTER_FIX_ABORT_ON_STALL"] = "0"
    run = budget
    run.send(:abort_run!, "stalled, test")

    assert_empty @killed
    assert(@said.any? { |line| line == "fix0: ABORT stalled, test" })
  end

  def git(*args) = Master::Io::Exec.capture2e("git", "-C", @root, "-c", "user.name=t", "-c", "user.email=t@t", *args)

  def test_a_protected_path_changed_by_the_run_trips_the_kill_switch_and_an_old_one_does_not
    git("init", "-q")
    tokens = File.join(@root, "MASTER", "data", "tokens.yml")
    other = File.join(@root, "MASTER", "data", "tokens_old.yml")
    FileUtils.mkdir_p(File.dirname(tokens))
    File.write(tokens, "a: 1\n")
    File.write(File.join(@root, "x.rb"), "x = 1\n")
    git("add", "-A")
    git("commit", "-q", "-m", "base")
    File.write(File.join(@root, "x.rb"), "x = 2\n")

    run = budget
    run.instance_variable_set(:@protected_baseline, Master::Fix::AutofixGuard.protected_changes(@root))
    @now = 301.0
    run.send(:guard_check, @now)
    assert_empty @killed, "an ordinary change is not a protected change"

    File.write(tokens, "a: 2\n")
    ENV["MASTER_FIX_ABORT_ON_STALL"] = "0"
    @now = 700.0
    run.send(:guard_check, @now)

    assert_equal 1, @killed.size
    assert_match(/protected path changed: MASTER\/data\/tokens\.yml/, @killed.first)
    assert(@said.any? { |line| line.include?("PROTECTED PATHS CHANGED") })
    refute File.exist?(other)
  end

  # Another writer's edit to STUDIO/postpro stopped a RAILS run fifty minutes in. A run's
  # guard watches the tree it can write; a protected change elsewhere is someone else's.
  def test_a_protected_change_outside_the_runs_tree_does_not_stop_it
    git("init", "-q")
    tokens = File.join(@root, "MASTER", "data", "tokens.yml")
    FileUtils.mkdir_p(File.dirname(tokens))
    File.write(tokens, "a: 1\n")
    git("add", "-A")
    git("commit", "-q", "-m", "base")

    run = budget
    run.instance_variable_set(:@protected_baseline, Master::Fix::AutofixGuard.protected_changes(@root))
    run.instance_variable_set(:@guard_scope, "RAILS/")
    File.write(tokens, "a: 2\n")
    @now = 301.0
    run.send(:guard_check, @now)

    assert_empty @killed
  end

  def test_the_wrapper_ends_a_run_on_the_no_yield_line_and_on_nothing_else_new
    line = "fix0: STALLED no yield: 0 fixed after 22m, 7 attempts\n"

    assert Operator::StallWatch.abort?(line, env: {})
    refute Operator::StallWatch.abort?("fix0: STALLED pass 1 phase fix for 3m, 0 files finished in 5m\n", env: {})
  end
end
