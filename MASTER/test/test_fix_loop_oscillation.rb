# frozen_string_literal: true

require_relative "test_helper"

class TestFixLoopOscillation < Minitest::Test
  class FakeBus
    attr_reader :events

    def initialize
      @events = []
      @subs = {}
    end

    def subscribe(pattern, &handler)
      (@subs[pattern] ||= []) << handler
    end

    def publish(event, payload = {})
      @events << { event: event, payload: payload }
      (@subs[event] || []).each { |h| h.call(payload) }
    end
  end

  # Returns the same fixed violation set on every scan call.
  class ConstantScanner
    def initialize(violations)
      @violations = violations
    end

    def scan(_path)
      Master::Result.ok(@violations.map { |violation| violation.merge(severity: :warning) })
    end
  end

  class SequenceScanner
    def initialize(scans)
      @scans = scans
      @index = 0
    end

    def scan(_path)
      scan = @scans.fetch(@index) { @scans.last }
      @index += 1
      Master::Result.ok(scan.map { |violation| violation.merge(severity: :warning) })
    end
  end

  # Agent with an open circuit — forces LLM pass to be skipped so
  # violations never clear, making oscillation observable in two passes.
  class OpenCircuitBreaker
    def open_models
      ["stub-model"]
    end
  end

  class OpenCircuitAgent
    def circuit_breaker
      OpenCircuitBreaker.new
    end
  end

  class RollbackSpy
    attr_reader :calls

    def initialize
      @calls = []
    end

    def call(result)
      @calls << result
      true
    end
  end

  class StubGit
    def dirty?(_)
      false
    end

    def add_all
      nil
    end

    def commit(_)
      nil
    end
  end

  class CountingFixLoop < Master::Fix::FixLoop
    attr_reader :run_count

    def initialize(*args, **kwargs)
      super
      @run_count = 0
    end

    def run(_target)
      @run_count += 1
      Master::Result.ok("cycle #{@run_count}")
    end
  end

  class CrashThenHaltFixLoop < Master::Fix::FixLoop
    attr_reader :run_count

    def initialize(*args, **kwargs)
      super
      @run_count = 0
    end

    def run(_target)
      @run_count += 1
      raise "first cycle failed" if @run_count == 1

      halt!(reason: "test complete")
    end
  end

  StubRule = Struct.new(:id, :severity)

  def setup
    @root = Dir.mktmpdir("fix_loop_osc_test")
    File.write(File.join(@root, "dummy.yml"), "---\n")
    @bus = FakeBus.new
  end

  def teardown
    FileUtils.remove_entry(@root) if @root && Dir.exist?(@root)
  end

  def build_loop(violations, rollback: nil)
    Master::Fix::FixLoop.new(
      rules: [StubRule.new("TEST_RULE", :warning)],
      agent: OpenCircuitAgent.new,
      scanner: ConstantScanner.new(violations),
      root: @root,
      bus: @bus,
      git: StubGit.new,
      rollback: rollback
    )
  end

  def build_loop_with_scanner(scanner)
    Master::Fix::FixLoop.new(
      rules: [StubRule.new("TEST_RULE", :warning)],
      agent: OpenCircuitAgent.new,
      scanner: scanner,
      root: @root,
      bus: @bus,
      git: StubGit.new
    )
  end

  def test_oscillation_fires_when_violation_set_repeats
    # Pass 1: snapshot recorded. Pass 2: same snapshot -> oscillation break.
    rollback = RollbackSpy.new
    loop = build_loop([{ rule: "TEST_RULE", file: "dummy.yml", line: 1, message: "osc" }], rollback: rollback)
    result = loop.run(@root)

    assert result.ok?
    pass_start = @bus.events.find { |e| e[:event] == "fix_loop:pass_start" }
    assert_equal 1, pass_start[:payload][:file_count]
    osc = @bus.events.select { |e| e[:event] == "fix_loop:oscillation" }
    assert_equal 1, osc.size
    assert_equal 1, osc.first[:payload][:violations]
    assert_equal 1, rollback.calls.size
    assert_equal :policy, rollback.calls.first.category
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

  def test_cycle_detector_fires_when_same_violation_recurs_without_identical_snapshot
    persistent = { rule: "TEST_RULE", file: "dummy.yml", line: 1, message: "still here" }
    scans = [
      [persistent],
      [persistent, { rule: "TEST_RULE", file: "dummy.yml", line: 2, message: "new" }],
      [persistent, { rule: "TEST_RULE", file: "dummy.yml", line: 3, message: "newer" }]
    ]
    loop = build_loop_with_scanner(SequenceScanner.new(scans))
    loop.run(@root, max_passes: 5)

    cycles = @bus.events.select { |e| e[:event] == "fix_loop:cycle_detected" }
    assert_equal 1, cycles.size
    assert_equal 3, cycles.first[:payload][:threshold]
    assert_equal persistent, cycles.first[:payload][:violation].to_h.slice(:file, :line, :rule, :message)
  end

  def test_run_forever_stops_after_max_cycles
    loop = CountingFixLoop.new(
      rules: [StubRule.new("TEST_RULE", :warning)],
      agent: OpenCircuitAgent.new,
      scanner: ConstantScanner.new([]),
      root: @root,
      bus: @bus,
      git: StubGit.new
    )
    loop.run_forever(@root, max_cycles: 2, startup_delay: 0, idle_sleep: 0)

    assert_equal 2, loop.run_count
    max_cycles = @bus.events.select { |e| e[:event] == "fix_loop:max_cycles" }
    assert_equal 1, max_cycles.size
    assert_equal 2, max_cycles.first[:payload][:cycles]
  end

  def test_run_forever_continues_after_cycle_error
    loop = CrashThenHaltFixLoop.new(
      rules: [StubRule.new("TEST_RULE", :warning)],
      agent: OpenCircuitAgent.new,
      scanner: ConstantScanner.new([]),
      root: @root,
      bus: @bus,
      git: StubGit.new
    )
    loop.run_forever(@root, max_cycles: 3, startup_delay: 0, idle_sleep: 0, cooldown_sleep: 0)

    assert_equal 2, loop.run_count
    errors = @bus.events.select { |e| e[:event] == "fix_loop:error" }
    assert_equal 1, errors.size
    assert_match(/first cycle failed/, errors.first[:payload][:error])
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

  def test_fix_loop_streams_per_file_scan_progress
    loop = build_loop([{ rule: "TEST_RULE", line: 1, message: "boom" }])

    out, = capture_io { loop.preview(@root) }

    assert_includes out, "scan: dummy.yml 1 violation(s)"
    assert @bus.events.any? { |event|
      event[:event] == "fix_loop:scan_progress" &&
        event[:payload][:file] == "dummy.yml" &&
        event[:payload][:count] == 1
    }
  end

  def test_collect_files_skips_binary_files
    init_git_repo(@root)
    text_path = File.join(@root, "tracked.txt")
    binary_path = File.join(@root, "blob.bin")
    File.write(text_path, "hello\n")
    File.binwrite(binary_path, "\x00\x01\x02")
    system("git", "-C", @root, "add", ".")

    files = build_loop([]).send(:collect_files, @root)

    assert_includes files, text_path
    refute_includes files, binary_path
  end

  def init_git_repo(root)
    system("git", "-C", root, "init", "-q")
  end
end
