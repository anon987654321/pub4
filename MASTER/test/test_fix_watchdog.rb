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

  def budget
    Budget.new(root: @root, max_passes: 8, env: {}, clock: -> { @now }, wall: -> { Time.at(1000) },
               out: ->(_) {}, say: ->(text) { @said << text }, poll_seconds: 0, killer: ->(reason) { @killed << reason }).start!
  end

  def test_no_fix_after_twenty_minutes_and_five_attempts_is_a_stall_that_aborts
    p = pulse
    5.times do |i|
      @now = 60.0 * (i + 1)
      p.observe("repair_loop:proposal_rejected", reason: "new_violations")
    end
    @now = 1199.0
    refute p.stall(@now)&.fetch(:abort, nil), "under twenty minutes it only reports"

    @now = 1261.0
    stalled = p.stall(@now)
    assert_equal "fix0: STALLED no yield: 0 fixed after 20m, 5 attempts", stalled[:line]
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
    @now = Pulse::STALL_SECONDS + 1

    stalled = p.stall(@now)

    assert_match(/STALLED pass 1 phase scan \+ stream fixes for 10m, 0 files attempted/, stalled[:line])
    refute stalled[:skippable]
    assert stalled[:abort], "direct CLI runs must not rely on the outer wrapper watchdog"
  end

  def test_an_advisory_pass_stall_is_skipped_instead_of_aborting_the_run
    p = pulse
    p.observe("fix_loop:phase", stage: :council)
    @now = Pulse::STALL_SECONDS + 1

    stalled = p.stall(@now)

    assert stalled[:skippable]
    refute stalled[:abort]
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
    @now = 700.0
    run.send(:guard_check, @now)

    assert_equal 1, @killed.size
    assert_match(/protected path changed: MASTER\/data\/tokens\.yml/, @killed.first)
    assert(@said.any? { |line| line.include?("PROTECTED PATHS CHANGED") })
    refute File.exist?(other)
  end

  def test_the_wrapper_ends_a_run_on_the_no_yield_line_and_on_nothing_else_new
    line = "fix0: STALLED no yield: 0 fixed after 22m, 7 attempts\n"

    assert Operator::StallWatch.abort?(line, env: {})
    refute Operator::StallWatch.abort?("fix0: STALLED pass 1 phase fix for 3m, 0 files finished in 5m\n", env: {})
  end
end
