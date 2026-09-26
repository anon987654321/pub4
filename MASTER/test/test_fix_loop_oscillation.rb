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
      @events << { event:, payload: }
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
  # The breaker only reports open for this agent's own model ("stub-model"),
  # matching LlmRouter's per-model check rather than a blanket any-model one.
  class OpenCircuitBreaker
    def open_models
      ["stub-model"]
    end

    def open?(model_id)
      model_id.to_s == "stub-model"
    end
  end

  class OpenCircuitAgent
    def circuit_breaker
      OpenCircuitBreaker.new
    end

    def model
      "stub-model"
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
    def changed_paths = []

    def commit(_message, paths:) = nil
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
      rollback:,
    ).tap { |loop| calm(loop) }
  end

  def build_loop_with_scanner(scanner)
    Master::Fix::FixLoop.new(
      rules: [StubRule.new("TEST_RULE", :warning)],
      agent: OpenCircuitAgent.new,
      scanner:,
      root: @root,
      bus: @bus,
      git: StubGit.new,
    ).tap { |loop| calm(loop) }
  end

  # ResourceBudget counts every process on the host, and a macOS desktop idles
  # above its process_count limit, so an unstubbed budget sheds model work and
  # the loop ends on the machine rather than on the violations.
  def calm(loop)
    budget = Master::Fix::ResourceBudget.new(root: @root)
    def budget.measure = { state: :ok, reasons: [] }
    loop.instance_variable_get(:@pass_runner).instance_variable_set(:@resource_budget, budget)
  end

  def test_oscillation_fires_when_violation_set_repeats
    # Pass 1: snapshot recorded. Pass 2: same snapshot -> oscillation break.
    rollback = RollbackSpy.new
    loop = build_loop([{ rule: "TEST_RULE", file: "dummy.yml", line: 1, message: "osc" }], rollback:)
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
      [persistent, { rule: "TEST_RULE", file: "dummy.yml", line: 3, message: "newer" }],
    ]
    loop = build_loop_with_scanner(SequenceScanner.new(scans))
    loop.run(@root, max_passes: 5)

    cycles = @bus.events.select { |e| e[:event] == "fix_loop:cycle_detected" }
    assert_equal 1, cycles.size
    assert_equal 3, cycles.first[:payload][:threshold]
    assert_equal persistent, cycles.first[:payload][:violation].to_h.slice(:file, :line, :rule, :message)
  end

  def test_run_forever_owns_the_supervisor_not_a_cycle_bound
    mission = Master::Fix::Mission.new(root: @root)
    mission.ensure_queued!(goal: "fix #{@root}", scope: @root)

    loop = build_loop([])
    supervisor = Master::Fix::Supervisor.new(root: @root, target: @root, fix_loop: loop)
    assert_respond_to supervisor, :run_forever
    assert_respond_to supervisor, :wake!
    assert_equal "waiting", Master::Fix::Mission.current(root: @root)["state"]
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

  # The boot scan halts the loop whenever lib/ carries a violation, which is
  # always; the operator's /fix exists to fix those, so it runs through a halt.
  def test_a_requested_run_proceeds_through_a_halt
    loop = build_loop([])
    loop.halt!(reason: "self_violation 1447 violations")

    result = loop.run(@root, requested: true)

    assert result.ok?, "a requested run was refused: #{result.message if result.err?}"
  end

  def test_fix_loop_streams_per_file_scan_progress
    loop = build_loop([{ rule: "TEST_RULE", line: 1, message: "boom" }])

    loop.preview(@root)

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
