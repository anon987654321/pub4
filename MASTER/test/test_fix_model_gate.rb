# frozen_string_literal: true

require_relative "test_helper"

# A /fix pinned to one lane failed every file of LaneSilence's five-minute cool-off at once, and its
# malformed replies began with the host at load 12.9 on 8 cores. ModelGate waits out the cool-off
# and lets a loaded host come down before the next model call, inside the run's deadline.
class TestFixModelGate < Minitest::Test
  Gate = Master::Fix::ModelGate
  Silence = Master::Io::LaneSilence
  Agent = Struct.new(:model)

  class Loads
    def initialize(*loads) = @loads = loads
    def load_pressure = [@loads.size > 1 ? @loads.shift : @loads.first, 12.0]
  end

  def teardown = Silence.record(true, Silence.lane_of("pinned:model"))

  def gate(resources, seconds_left: 3_600, &after_sleep)
    slept = []
    sleeper = lambda do |seconds|
      slept << seconds
      after_sleep&.call(slept.size)
    end
    Master::Fix::RunBudget.stub(:seconds_left, seconds_left) do
      Master::Fix::RunBudget.stub(:stopping, nil) do
        capture_io { Gate.before_call(Agent.new("pinned:model"), resources:, sleeper:) }
      end
    end
    slept
  end

  def test_a_pinned_lane_in_its_cool_off_is_waited_out
    Silence.silence(Silence.lane_of("pinned:model"), reason: "malformed tool-call response")

    slept = gate(Loads.new(4.0)) { |polls| Silence.record(true, Silence.lane_of("pinned:model")) if polls == 3 }

    assert_equal [Gate::POLL_S] * 3, slept
  end

  def test_a_loaded_host_is_given_time_to_come_down
    assert_equal [Gate::POLL_S] * 2, gate(Loads.new(12.9, 12.5, 6.0))
  end

  def test_the_load_wait_is_bounded
    assert_equal Gate::LOAD_WAIT_MAX_S / Gate::POLL_S, gate(Loads.new(20.0)).size
  end

  def test_nothing_waits_outside_a_run_or_near_its_deadline
    Silence.silence(Silence.lane_of("pinned:model"))

    assert_empty gate(Loads.new(20.0), seconds_left: nil)
    assert_empty gate(Loads.new(20.0), seconds_left: Gate::RESERVE_S)
  end

  def test_a_lane_that_answers_and_a_quiet_host_cost_nothing
    assert_empty gate(Loads.new(3.0))
  end
  def test_a_paced_run_is_not_read_as_stalled
    now = 0.0
    pulse = Master::Fix::RunPulse.new(max_passes: 2, clock: -> { now }, load: -> { 0.0 })
    pulse.observe("fix_loop:pass_start", { pass: 1, file_count: 4 })
    now = Master::Fix::FixTime.stall_s + 30.0
    pulse.observe("fix_loop:model_wait", { reason: "pinned:model is in its cool-off" })

    assert_nil pulse.stall(now)
    assert pulse.stall(now + pulse.send(:finish_window) + 1), "a wait that stopped polling is a stall again"
  end

  # The repair asks the gate before every model call.
  def test_the_repair_loop_paces_its_model_call
    asked = []
    loop = Master::Fix::RepairLoop.new(law: Struct.new(:id, :severity).new("TEST_RULE", :warning),
                                       agent: Agent.new("pinned:model"), scanner: nil, root: Dir.tmpdir)
    %i[autofix_allowed? fingerprint_matches?].each { |name| loop.define_singleton_method(name) { |*| true } }
    loop.define_singleton_method(:request_fix) { |*| nil }

    outcome = Gate.stub(:before_call, ->(agent, **) { asked << agent.model }) do
      loop.send(:attempt_fix, { law: "TEST_RULE", file: "a.rb", line: 1, severity: :warning })
    end

    assert_equal :no_proposal, outcome
    assert_equal ["pinned:model"], asked
  end
end
