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
      root: @root, bus: @bus, git: StubGit.new, ground_truth:,
    )
    runner = loop.instance_variable_get(:@pass_runner)
    runner.instance_variable_set(:@council, council) if council
    loop
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

  # 2-4. /fix observes, repairs what the reading found, and observes again.
  def test_fix_observes_repairs_and_observes_again
    seen = []
    repaired = []
    fix_loop = Object.new
    fix_loop.define_singleton_method(:run) { |target, **| repaired << target; Master::Result.ok("DONE: clean") }
    fix_loop.define_singleton_method(:preview) { |_| Master::Result.ok(total: 0, rules: {}, files: {}) }
    scanner = Object.new
    def scanner.scan(*) = Master::Result.ok([])
    def scanner.scan_dir(*) = Master::Result.ok([])

    out = Master::CLI::CommandRegistry.stub(:observe, ->(*, **kw) { seen << kw[:ctx][:args]; "clean" }) do
      Master::CLI::CommandRegistry.dispatch_fix(
        scanner:, fix_loop:, deliberation: nil, root: Master::ROOT, bus: nil,
        ctx: { args: "lib/io --no-aesthetic" },
      )
    end

    assert_equal 2, seen.size, "a fix observes before and after the repair"
    assert_equal 1, repaired.size, "the repair runs between the two readings"
    assert_includes out.lines.map(&:chomp), "observe"
    assert_includes out.lines.map(&:chomp), "re-observe"
  end

  # 9. The council argues inside the loop, and 11: its pick reaches the repair.
  def test_the_council_runs_inside_the_pass_and_its_picks_reach_the_repair
    council = Object.new
    asked = []
    council.define_singleton_method(:run) do |files:, pass:, deadline:|
      asked << { files:, pass: }
      { feedback: [{ feedback: "the name hides the intent" }], cherry_picks: ["rename the flag to what it gates"] }
    end
    loop = build_loop([{ rule: "TEST_RULE", file: File.join(@root, "dummy.yml"), line: 1, message: "x" }],
                      council:)
    runner = loop.instance_variable_get(:@pass_runner)

    loop.run(@root, max_passes: 1)

    refute_empty asked, "the council never ran inside the pass"
    preamble = runner.send(:council_preamble, { cherry_picks: ["rename the flag to what it gates"] })
    assert_includes preamble, "rename the flag to what it gates"
    assert_nil runner.send(:council_preamble, { cherry_picks: [] })
  end

  # 6. A clean tree the ground truth agrees with is the one state that says DONE.
  def test_a_converged_run_is_done
    result = build_loop([]).run(@root)

    assert result.ok?
    assert_match(/\ADONE: /, result.value!)
  end

  # 7. Running out of passes is not finishing.
  def test_a_pass_limit_is_a_plateau_not_a_done
    violations = [{ rule: "TEST_RULE", file: File.join(@root, "dummy.yml"), line: 1, message: "stays" }]
    result = build_loop(violations).run(@root, max_passes: 2)

    assert result.ok?
    assert_match(/\APLATEAU: /, result.value!)
    refute_match(/DONE/, result.value!)
  end

  # 13. A repair the tree refuses cannot read as a finished tree.
  def test_a_ground_truth_that_keeps_refusing_is_a_validation_failure
    ground_truth = Object.new
    def ground_truth.assert_fresh!(path, reason:) = Master::Result.err("stale #{path} (#{reason})", category: :validation)

    result = build_loop([], ground_truth:).run(@root, max_passes: 5)

    assert_match(/\AVALIDATION_FAILED: /, result.value!)
  end

  # 14. A halt is the loop saying the decision is not its to make.
  def test_a_halted_loop_is_blocked
    loop = build_loop([])
    loop.halt!(reason: "self_violation")

    result = loop.run(@root, requested: false)

    assert_predicate result, :err?
    assert_match(/\ABLOCKED: /, result.message)
  end

  # 10 and 12. Every issue keeps its strongest proposal, the field is capped,
  # and a heading is not a proposal.
  def test_cherry_pick_keeps_one_repair_per_issue_and_caps_the_field
    feedback = [{ feedback: "issue 1 the flag name hides what it gates" },
                { feedback: "issue 2 the retry has no ceiling" }]
    ideas = (["Solutions:"] +
             Array.new(25) { |i| "issue 1 rename the flag, variant #{i} hides gates name" } +
             ["issue 2 cap the retry with a ceiling and backoff"]).join("\n")

    picks = Master::Review::Council::Critique::CherryPick.rank(feedback, ideas)

    assert_operator picks.size, :<=, Master::Review::Council::Critique::CherryPick::LIMIT
    assert(picks.any? { |pick| pick.include?("cap the retry") }, "the second issue lost its only proposal")
    refute_includes picks, "Solutions:"
  end
end
