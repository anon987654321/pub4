# frozen_string_literal: true

require "test_helper"
require "minitest/mock"
require_relative "support_council_answer"

# A /fix run once sat 39 minutes in its first council, 186 seconds per call on a
# free model, and never reached a file. The council is advisory: every call has a
# wall-clock deadline that really interrupts it, the whole council has a budget,
# a lane that blows its deadline stays quiet, and a stalled advisory phase is cut.
class TestCouncilDeadline < Minitest::Test
  Clock = Master::Review::LLMDispatcher::PassClock
  Silence = Master::Io::LaneSilence

  def setup
    @saved = %w[MASTER_COUNCIL_CALL_TIMEOUT_S MASTER_COUNCIL_PASS_BUDGET_S MASTER_FIX_COUNCIL MASTER_FIX_STALL_S].to_h { |k| [k, ENV.delete(k)] }
    Clock.reset_cancel!
  end

  def teardown
    @saved.each { |k, v| v.nil? ? ENV.delete(k) : ENV[k] = v }
    Clock.reset_cancel!
    Silence.record(true, "claude-cli")
  end

  def test_defaults_are_two_minutes_per_call_and_ten_per_council
    assert_equal 120, Clock.call_timeout_s
    assert_equal 600, Clock.pass_budget_s
    ENV["MASTER_COUNCIL_CALL_TIMEOUT_S"] = "7"
    assert_equal 7, Clock.call_timeout_s
  end

  def test_a_call_deadline_is_the_tightest_of_the_three
    assert_equal 300, Clock.call_deadline(300), "outside a council the dispatcher's own deadline stands"
    Clock.within(600) { assert_equal 120, Clock.call_deadline(300) }
    Clock.within(30) { assert_operator Clock.call_deadline(300), :<=, 30 }
    refute Clock.active?
  end

  def test_the_budget_expires_and_a_cancel_expires_it_early
    Clock.within(0.05) do
      refute Clock.expired?
      sleep 0.1
      assert Clock.expired?
    end
    refute Clock.expired?
    Clock.cancel!("stalled")
    assert Clock.expired?
    Clock.reset_cancel!
    refute Clock.expired?
  end

  def door(calls, &answer)
    door = Master::Review::LLMDispatcher.allocate
    door.instance_variable_set(:@bus, nil)
    door.instance_variable_set(:@model_router, nil)
    door.instance_variable_set(:@cache, Object.new.tap { |c| c.define_singleton_method(:fetch) { |_k, _m, &blk| blk.call } })
    door.instance_variable_set(:@circuit_breaker, Object.new.tap { |c| c.define_singleton_method(:call) { |_cost, &blk| blk.call } })
    door.instance_variable_set(:@availability, Struct.new(:dispatch_deadline_s).new(300))
    door.define_singleton_method(:send_llm_request) { |model, *_a, **_k| calls << model; answer.call(model) }
    door
  end

  def test_a_free_lane_timeout_outside_a_council_is_recorded_and_parked
    model = "openrouter/deadline-regression:free"
    calls = []
    dispatcher = door(calls) { |_model| sleep 30; Master::Result.ok("late") }
    msg = [{ role: "user", content: "large repair prompt" }]

    started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    result = Master::Trace::Dmesg.stub(:status, ->(*) {}) do
      Master::Io::LaneSelection.stub(:free_call_timeout_s, 0.05) do
        Master.stub(:llm_reachable?, true) { dispatcher.send_with_cache(model, msg) }
      end
    end
    elapsed = Process.clock_gettime(Process::CLOCK_MONOTONIC) - started

    assert_operator elapsed, :<, 2, "the request exceeded its hard timeout"
    assert_equal :timeout, result.category
    assert Silence.silent?(Silence.lane_of(model)), "the stalled provider was not parked"
    assert Master::Io::ModelSkipCache.skipped?(model), "the timeout was not recorded for failover"
    assert_equal [model], calls
  ensure
    Silence.record(true, Silence.lane_of(model)) if model
    Master::Io::ModelSkipCache.clear!
  end

  def test_a_slow_call_is_interrupted_and_its_lane_is_not_asked_again
    ENV["MASTER_COUNCIL_CALL_TIMEOUT_S"] = "1"
    calls = []
    dispatcher = door(calls) { |_model| sleep 30; Master::Result.ok("late") }
    msg = [{ role: "user", content: "hi" }]

    started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    first = Master.stub(:llm_reachable?, true) { Clock.within(60) { dispatcher.send_with_cache("claude-cli:claude-opus-5-5", msg) } }
    took = Process.clock_gettime(Process::CLOCK_MONOTONIC) - started

    assert_operator took, :<, 5, "the call was waited out instead of interrupted"
    assert_equal :timeout, first.category
    assert Silence.silent?("claude-cli"), "the lane that blew its deadline is silent"

    second = Master.stub(:llm_reachable?, true) { Clock.within(60) { dispatcher.send_with_cache("claude-cli:claude-sonnet-5-5", msg) } }
    assert second.err?
    assert_equal ["claude-cli:claude-opus-5-5"], calls, "a silent lane is never asked again this run"
  end

  def test_calls_are_refused_once_the_council_budget_is_spent
    calls = []
    dispatcher = door(calls) { |_m| Master::Result.ok("ok") }
    result = Master.stub(:llm_reachable?, true) do
      Clock.within(0.01) { sleep 0.05; dispatcher.send_with_cache("deepseek-chat", [{ role: "user", content: "hi" }]) }
    end
    assert_equal :timeout, result.category
    assert_empty calls
  end

  Persona = Struct.new(:name, :role, :bias, :prompt, :veto_role, :emphasizes, keyword_init: true) do
    def veto? = !!veto_role
  end

  def test_a_council_past_its_budget_returns_what_answered_and_says_so
    agent = Object.new
    count = 0
    lock = Mutex.new
    agent.define_singleton_method(:ask) do |_prompt, **|
      n = lock.synchronize { count += 1 }
      n <= 2 ? CouncilAnswer.json : sleep(30)
    end
    personas = Array.new(6) { |i| Persona.new(name: "P#{i}", role: "r", bias: "b", prompt: "p") }
    delib = Master::Review::Council::Deliberation.new(personas:, agent:, judge_enabled: false)
    lines = []

    started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    result = Master::Trace::Dmesg.stub(:status, ->(unit, msg, **) { lines << "#{unit}: #{msg}" }) do
      Master.stub(:llm_reachable?, true) do
        Master::Review::Council::Deliberation.stub(:reachable_for?, true) { Clock.within(1) { delib.review("x = 1") } }
      end
    end
    took = Process.clock_gettime(Process::CLOCK_MONOTONIC) - started

    assert_operator took, :<, 8, "the council waited for its slow personas"
    assert result.ok?, result.respond_to?(:message) ? result.message : result.inspect
    assert_equal 2, result.value!.size
    assert_includes lines, "council0: skipped, deadline 1s (2 of 6 personas answered)"
  end

  def test_the_heartbeat_names_the_phase_and_the_council_progress
    pulse = Master::Fix::RunPulse.new(max_passes: 8, clock: -> { 100.0 }, load: -> { 0.5 })
    pulse.observe("fix_loop:pass_start", { pass: 1, file_count: 10 })
    assert_match(/ phase scan /, pulse.line(elapsed: 5, tokens: 0, eta: nil))

    pulse.observe("fix_loop:phase", { stage: :council })
    pulse.observe("council:progress", { answered: 2, total: 5 })
    assert_includes pulse.line(elapsed: 5, tokens: 0, eta: nil), "phase council (2 of 5 personas answered)"

    pulse.observe("fix_loop:phase", { stage: :model_fixes })
    pulse.observe("repair_loop:pass", { law: "NO_GOD_CLASS", violations: 1, fixed: 0 })
    pulse.observe("scan:progress", { done: 3, total: 10, path: "/x/lib/big.rb" })
    assert_includes pulse.line(elapsed: 5, tokens: 0, eta: nil), "phase fix NO_GOD_CLASS big.rb"
  end

  def test_a_stalled_advisory_phase_is_reported_and_cut
    now = 0.0
    pulse = Master::Fix::RunPulse.new(max_passes: 8, clock: -> { now }, load: -> { 0.0 })
    pulse.observe("fix_loop:pass_start", { pass: 3, file_count: 10 })
    pulse.observe("fix_loop:phase", { stage: :council })
    now = 599.0
    assert_nil pulse.stall(now)

    now = 601.0
    stalled = pulse.stall(now)
    assert_equal "fix0: STALLED pass 3 phase council for 10m, 0 files attempted", stalled[:line]
    assert stalled[:skippable]

    said = []
    budget = Master::Fix::RunBudget.allocate
    budget.instance_variable_set(:@pulse, pulse)
    budget.instance_variable_set(:@clock, -> { now })
    budget.instance_variable_set(:@say, ->(line) { said << line })
    budget.send(:watch_for_stall)

    assert_equal [stalled[:line]], said
    assert Clock.expired?, "the stalled council was not cancelled"
  end

  def test_a_stall_in_the_fix_stream_aborts_the_run
    now = 0.0
    pulse = Master::Fix::RunPulse.new(max_passes: 8, clock: -> { now }, load: -> { 0.0 })
    pulse.observe("fix_loop:pass_start", { pass: 1, file_count: 10 })
    pulse.observe("fix_loop:phase", { stage: :model_fixes })
    now = 700.0
    stalled = pulse.stall(now)

    refute stalled[:skippable]
    assert stalled[:abort], "a non-advisory stream stall must stop the run"
  end

  # A finished file keeps the pass alive for five minutes; silence after that is
  # a stall again, and the line says files finished, not attempted.
  def test_an_attempted_fix_ends_the_stall_for_five_minutes
    now = 0.0
    pulse = Master::Fix::RunPulse.new(max_passes: 8, clock: -> { now }, load: -> { 0.0 })
    pulse.observe("fix_loop:pass_start", { pass: 1, file_count: 10 })
    now = 650.0
    pulse.observe("repair_loop:fix_applied", {})
    now = 900.0
    assert_nil pulse.stall(now)

    now = 1000.0
    assert_equal "fix0: STALLED pass 1 phase scan for 16m, 0 files finished in 5m", pulse.stall(now)[:line]
  end

  def test_the_off_switch_asks_no_council_at_all
    ENV["MASTER_FIX_COUNCIL"] = "0"
    round = Master::Fix::FixLoop::CouncilRound.new(agent: Object.new, root: Master::ROOT)
    boom = ->(*, **) { raise "the council was convened" }
    Master::Review::Council::Critique.stub(:new, boom) do
      assert_nil round.run(files: [__FILE__], pass: 1, deadline: Time.now + 60)
      assert_nil round.improve(files: [__FILE__], pass: 1, deadline: Time.now + 60)
    end
  end

  def test_the_council_before_the_fixes_gets_two_minutes
    round = Master::Fix::FixLoop::CouncilRound.new(agent: Object.new, root: Master::ROOT)
    assert_equal 120, round.send(:before_fixes_budget)
    ENV["MASTER_COUNCIL_PASS_BUDGET_S"] = "30"
    assert_equal 30, round.send(:before_fixes_budget)
  end
end
