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
    assert_equal "RAILS", verified.first
    assert_includes result, "DONE: clean"
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
  # injected double would pass just as well against a loop that never built it.
  def test_a_fix_loop_carries_a_council_of_its_own
    runner = build_loop([]).instance_variable_get(:@pass_runner)

    assert_instance_of Master::Fix::FixLoop::CouncilRound, runner.instance_variable_get(:@council)
  end

  def test_a_fix_loop_builds_a_visual_pass
    runner = build_loop([]).instance_variable_get(:@pass_runner)

    assert_instance_of Master::Fix::VisualPass, runner.instance_variable_get(:@visual_pass)
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
  def test_a_clean_pass_asks_council_for_improvements
    asked = []
    council = Object.new
    council.define_singleton_method(:improve) do |files:, pass:, deadline:|
      asked << { files:, pass: }
      []
    end
    result = build_loop([], council:).run(@root, max_passes: 2)

    assert result.ok?
    assert_match(/\ADONE: /, result.value!)
    assert_equal 1, asked.size, "the first clean streak pass should invoke proactive review once"
    refute_empty asked.first[:files]
  end

  def test_council_improvements_require_a_file_and_line_or_symbol_anchor
    file = File.join(@root, "dummy.yml")
    round = Master::Fix::FixLoop::CouncilRound.new(agent: nil, root: @root, bus: @bus)
    anchored = round.send(
      :improvement_findings,
      { cherry_picks: ["dummy.yml line 1: simplify the redundant empty declaration"] },
      [file],
    )
    unanchored = round.send(
      :improvement_findings,
      { cherry_picks: ["simplify the redundant empty declaration"] },
      [file],
    )

    assert_equal 1, anchored.size
    assert_equal file, anchored.first[:file]
    assert_equal 1, anchored.first[:line]
    assert_empty unanchored
    assert_equal :improvement, anchored.first[:kind]
  end

  def test_clean_tree_ideation_demands_anchored_candidates
    critique = Master::Review::Council::Critique.new(mode: :general, agent: nil)
    prompt = critique.send(:ideation_prompt, [])

    assert_includes prompt, "5 to 20 materially different candidates"
    assert_includes prompt, "repository-relative file and stable line or symbol"
    assert_includes prompt, "Do not invent defects"
  end

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

  def test_cherry_pick_reads_brainstorm_ideas_not_only_the_final_synthesis
    result = Master::Result.ok(
      ideas: ["issue 1 small repair", "issue 2 distinct repair"],
      critiques: [],
      final: "synthesis",
    )

    text = Master::Review::Council::Critique::CherryPick.ideas_text(result)

    assert_includes text, "issue 1 small repair"
    assert_includes text, "issue 2 distinct repair"
    assert_includes text, "synthesis"
  end

  # The preview printed two Ruby hashes through #inspect: one line past the
  # width of any terminal, with the counts that matter wherever the wrap put
  # them, and every file named by its full path inside a tree the pass has
  # already named.
  def test_the_repair_preview_reads_as_lines
    pass = Master::CLI::Pipeline::Pass.allocate
    counts = { "FEW_ARGUMENTS" => 28, "magic_number" => 26, "FEATURE_ENVY" => 14,
               "CQS" => 9, "SMALL_FILES" => 6, "COUPLER_SMELLS" => 5, "duplicate_code" => 4 }
    lines = pass.send(:preview_lines, total: 107, rules: counts, files: { "lib/voice/engines.rb" => 20 })

    assert_equal "preview: 107 repairs", lines.lines.first.chomp
    assert_match(/^preview rules: FEW_ARGUMENTS 28, /, lines)
    assert_match(/, and 1 more$/, lines.lines[1].chomp)
    assert_equal "preview files: engines.rb 20", lines.lines[2].chomp
    refute_match(/lib.voice.engines/, lines)
  end

  def test_one_repair_is_not_repairs
    pass = Master::CLI::Pipeline::Pass.allocate
    assert_equal "preview: 1 repair", pass.send(:preview_lines, total: 1, rules: {}, files: {})
  end
end