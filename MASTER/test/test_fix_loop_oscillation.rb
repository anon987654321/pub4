# frozen_string_literal: true

require_relative "test_helper"

class TestFixLoopOscillation < Minitest::Test
  class FakeBus
    attr_reader :events

    def initialize
      @events = []
      @subs = {}
    end

    def subscribe(pattern, &handler) = (@subs[pattern] ||= []) << handler

    def publish(event, payload = {})
      @events << { event:, payload: }
      (@subs[event] || []).each { |h| h.call(payload) }
    end
  end

  # Returns the same fixed violation set on every scan call.
  class ConstantScanner
    def initialize(violations) = @violations = violations
    def scan(_path) = @violations.dup
  end

  # Agent with an open circuit — forces LLM pass to be skipped so
  # violations never clear, making oscillation observable in two passes.
  class OpenCircuitBreaker
    def open_models = ["stub-model"]
  end

  class OpenCircuitAgent
    def circuit_breaker = OpenCircuitBreaker.new
  end

  class StubGit
    def dirty?(_) = false
    def add_all = nil
    def commit(_) = nil
  end

  StubRule = Struct.new(:id, :severity)

  def setup
    @root = Dir.mktmpdir("fix_loop_osc_test", Dir.home)
    File.write(File.join(@root, "dummy.yml"), "---\n")
    @bus = FakeBus.new
  end

  def teardown
    FileUtils.remove_entry(@root) if @root && Dir.exist?(@root)
  end

  def build_loop(violations)
    Master::Loop::FixLoop.new(
      rules: [StubRule.new("TEST_RULE", :warning)],
      agent: OpenCircuitAgent.new,
      scanner: ConstantScanner.new(violations),
      root: @root,
      bus: @bus,
      git: StubGit.new
    )
  end

  def test_oscillation_fires_when_violation_set_repeats
    # Pass 1: snapshot recorded. Pass 2: same snapshot -> oscillation break.
    loop = build_loop([{ rule: "TEST_RULE", file: "dummy.yml", line: 1, message: "osc" }])
    result = loop.run(@root)

    assert result.ok?
    osc = @bus.events.select { |e| e[:event] == "fix_loop:oscillation" }
    assert_equal 1, osc.size
    assert_equal 1, osc.first[:payload][:violations]
  end

  def test_oscillation_does_not_fire_when_violations_clear
    # Empty violation set -> clean path, no oscillation.
    loop = build_loop([])
    result = loop.run(@root)

    assert result.ok?
    osc = @bus.events.select { |e| e[:event] == "fix_loop:oscillation" }
    assert_empty osc
    events = @bus.events.map { |event| event[:event] }
    assert_includes events, "fix_loop:ground_truth_ok"
    assert events.index("fix_loop:ground_truth_ok") < events.index("fix_loop:clean")
  end

  def test_oscillation_fires_once_not_every_pass
    # Even if max_passes is high, oscillation fires exactly once then stops.
    loop = build_loop([{ rule: "TEST_RULE", file: "dummy.yml", line: 1, message: "osc" }])
    loop.run(@root, max_passes: 10)

    osc = @bus.events.select { |e| e[:event] == "fix_loop:oscillation" }
    assert_equal 1, osc.size
  end

  def test_halt_blocks_fix_loop_run
    loop = build_loop([])

    halt = loop.halt!(reason: "self_violation 2 violations")
    result = loop.run(@root)

    assert halt.ok?
    assert result.err?
    assert_equal :policy, result.category
    assert_match(/self_violation 2 violations/, result.message)
    assert @bus.events.any? { |event| event[:event] == "fix_loop:halt" }
  end
end
