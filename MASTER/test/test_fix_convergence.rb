# frozen_string_literal: true

require_relative "test_helper"
require "tmpdir"

# /fix is the whole improvement operation: it observes, lets the council argue,
# repairs, and observes again, and it ends in a state that says what actually
# happened. /scan is gone — a reading nobody acts on was the thing it named.
class TestFixConvergence < Minitest::Test
  StubRule = Struct.new(:id, :severity)

  class FakeBus
    attr_reader :events

    def initialize = @events = []
    def subscribe(*) = nil
    def publish(event, payload = {}) = @events << { event:, payload: }
    def names = @events.map { |row| row[:event] }
  end

  class ConstantScanner
    def initialize(violations) = @violations = violations
    def scan(_path) = Master::Result.ok(@violations.map { |v| v.merge(severity: :warning) })
  end

  class OpenCircuitAgent
    Breaker = Struct.new(:ignored) do
      def open_models = ["stub-model"]
      def open?(model_id) = model_id.to_s == "stub-model"
    end

    def circuit_breaker = Breaker.new(nil)
    def model = "stub-model"
  end

  class StubGit
    def changed_paths = []
    def commit(_message, paths:) = nil
  end

  def setup
    @root = Dir.mktmpdir("fix_convergence")
    File.write(File.join(@root, "dummy.yml"), "---\n")
    @bus = FakeBus.new
  end

  def teardown
    FileUtils.remove_entry(@root) if @root && Dir.exist?(@root)
  end

  def build_loop(violations, ground_truth: nil, council: nil)
    loop = Master::Fix::FixLoop.new(
      rules: [StubRule.new("TEST_RULE", :warning)],
      agent: OpenCircuitAgent.new,
      scanner: ConstantScanner.new(violations),
      root: @root, bus: @bus, git: StubGit.new, ground_truth:
    )
    runner = loop.instance_variable_get(:@pass_runner)
    runner.instance_variable_set(:@council, council) if council
    runner.instance_variable_set(:@resource_budget, calm_budget)
    loop
  end

  # ResourceBudget counts every process on the host, and a macOS desktop idles
  # above its process_count limit, so an unstubbed budget sheds model work and
  # these runs plateau on the machine rather than on the loop.
  def calm_budget
    budget = Master::Fix::ResourceBudget.new(root: @root)
    def budget.measure = { state: :ok, reasons: [] }
    budget
  end

  # 1. /scan is not a public command, in the registry or in the router.
  def test_scan_is_not_a_command
    refute_includes Master::CLI::TurnRouter::PIPELINE_SLASH, "scan"
    refute_includes Master::CLI::TurnRouter::PIPELINE_COMMANDS, "scan"
    refute Master::CLI::CommandRegistry::HELP_TOPICS.key?("scan")
    refute Master::CLI::CommandRegistry.respond_to?(:dispatch_scan)
    assert_includes Master::CLI::Pipeline::Pass::STAGES, "fix"
    refute_includes Master::CLI::Pipeline::Pass::STAGES, "scan"
  end

  def test_bare_fix_resolves_to_the_pub4_root
    resolver = Class.new do
      include Master::CLI::Pipeline::TargetResolver
      def initialize(root) = @root = root
    end.new(Master::ROOT)

    assert_equal Master::REPO_ROOT, resolver.resolve_target("")
    assert_equal Master::REPO_ROOT, resolver.resolve_target("everything")
    assert_equal Master::RAILS_ROOT, resolver.resolve_target("RAILS")
  end

  # 2-4. /fix observes, repairs what the reading found, and observes again.
  def test_fix_reenters_after_gate_repairs_until_the_tree_stabilises
    verified = []
    states = [[0, ["RAILS/app/models/item.rb"]], [0, []]]
    fix_loop = Object.new
    fix_loop.define_singleton_method(:run) { |target, **| Master::Result.ok("DONE: clean") }
    fix_loop.define_singleton_method(:preview) { |_| Master::Result.ok(total: 0, rules: {}, files: {}) }
    scanner = Object.new
    def scanner.scan(*) = Master::Result.ok([])
    def scanner.scan_dir(*) = Master::Result.ok([])

    result = Operator::GateChain.stub(:verify_fix, ->(target:) { verified << target; states.shift }) do
      Master::CLI::CommandRegistry.stub(:observe, ->(*) { "clean" }) do
        Master::CLI::CommandRegistry.dispatch_fix(
          scanner:, fix_loop:, deliberation: nil, root: Master::ROOT, bus: nil,
          ctx: { args: "RAILS --no-aesthetic" }
        )
      end
    end

    assert_equal 2, verified.size
    assert_equal Master::RAILS_ROOT, verified.first
    assert_includes result, "DONE: clean"
  end

  def test_fix_observes_repairs_and_observes_again
    seen = []
    repaired = []
    fix_loop = Object.new
    fix_loop.define_singleton_method(:run) { |target, **| repaired << target; Master::Result.ok("DONE: clean") }
    fix_loop.define_singleton_method(:preview) { |_| Master::Result.ok(total: 0, rules: {}, files: {}) }
    scanner = Object.new
    def scanner.scan(*) = Master::Result.ok([])
    def scanner.scan_dir(*) = Master::Result.ok([])

    # The proof after a writing pass is MASTER's whole suite, which holds this
    # test; stubbed, so the test measures the pass rather than the suite.
    suites = ->(*) { [true, ["suites: 1/1 green"], 0] }
    out = Operator::GateChain.stub(:suites, suites) do
      Master::CLI::CommandRegistry.stub(:observe, ->(*, **kw) { seen << kw[:ctx][:args]; "clean" }) do
        Master::CLI::CommandRegistry.dispatch_fix(
          scanner:, fix_loop:, deliberation: nil, root: Master::ROOT, bus: nil,
          ctx: { args: "lib/io --no-aesthetic" }
        )
      end
    end

    assert_equal 2, seen.size, "a fix observes before and after the repair"
    assert_equal 1, repaired.size, "the repair runs between the two readings"
    assert_includes out.lines.map(&:chomp), "observe"
    assert_includes out.lines.map(&:chomp), "re-observe"
  end

  # A suite run as a proof holds tests that run /fix; their proof must not
  # start the suites again, or each level spawns the next without end.
  def test_a_proof_started_inside_a_proof_is_skipped
    pass = Master::CLI::Pipeline::Pass.allocate
    ran = false
    saved = ENV["MASTER_IN_PROOF"]
    ENV["MASTER_IN_PROOF"] = "1"
    name, body = Operator::GateChain.stub(:suites, ->(*) { ran = true; [true, [], 0] }) do
      pass.send(:proof_section, Master::ROOT)
    end

    assert_equal "proof", name
    assert_match(/already inside a proof run/, body) # source-assertion: ok — the section proof_section returned
    refute ran, "the nested proof ran the suites"
  ensure
    ENV["MASTER_IN_PROOF"] = saved
  end

  # runner.rb's exit 3 is "nothing failed, some gates measured nothing"; the
  # proof passes on it and names the gap, and still fails on exit 1.
  def test_rails_proof_passes_an_inconclusive_run_and_fails_a_failed_one
    pass = Master::CLI::Pipeline::Pass.allocate
    _name, runner = pass.send(:proof_runner, Master::RAILS_ROOT)

    inconclusive = ->(**) { [false, ["deploy_drift measured nothing"], 3] }
    ok, out = Operator::GateChain.stub(:rails_gates, inconclusive) { runner.call }
    assert ok, "an inconclusive gate blocked the proof"
    assert_match(/GATE_STRICT_INCONCLUSIVE/, out.last) # source-assertion: ok — the proof's own report line

    failed = ->(**) { [false, ["port_inventory failed"], 1] }
    ok, = Operator::GateChain.stub(:rails_gates, failed) { runner.call }
    refute ok, "a failed gate passed the proof"
  end

  def test_a_proof_marks_its_children_and_restores_the_parent
    pass = Master::CLI::Pipeline::Pass.allocate
    saved = ENV.delete("MASTER_IN_PROOF")

    assert_equal "1", pass.send(:inside_proof) { ENV["MASTER_IN_PROOF"] }
    assert_nil ENV["MASTER_IN_PROOF"]
  ensure
    ENV["MASTER_IN_PROOF"] = saved
  end

  # The loop builds its own council: the test below injects one, and an