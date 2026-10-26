# frozen_string_literal: true

require_relative "test_helper"
require "tmpdir"
require "digest"
require "json"
require_relative "../lib/operator/check_chain"

# /fix is the whole improvement operation: it observes, lets the council argue,
# repairs, and observes again, and it ends in a state that says what actually
# happened. /scan has no separate operation; its compatibility spelling rewrites to /fix.
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
    def scan(_path, depth: :deep, laws: nil) = Master::Result.ok(@violations.map { |v| v.merge(severity: :warning) })
  end

  class OpenCircuitAgent
    Breaker = Struct.new(:ignored) do
      def open_models = ["stub-model"]
      def open?(model_id) = model_id.to_s == "stub-model"
    end

    def circuit_breaker = Breaker.new(nil)
    def model = "stub-model"
  end

  class RecordingAgent
    def initialize(reply) = @reply = reply
    def ask(_prompt) = @reply
  end

  class StubGit
    def changed_paths = []
    def commit(_message, paths:) = nil
  end

  def setup
    @previous_deep_trace = ENV["MASTER_FIX_DEEP_TRACE"]
    ENV["MASTER_FIX_DEEP_TRACE"] = "0"
    @root = Dir.mktmpdir("fix_convergence")
    File.write(File.join(@root, "dummy.yml"), "---\n")
    # Sacred paths fail closed without a soul.yml, so every fixture file would
    # read as immutable and the corpus would collect nothing.
    Dir.mkdir(File.join(@root, "data"))
    File.write(File.join(@root, "data", "soul.yml"), "absolute:\n  sacred_paths:\n    - data/soul.yml\n")
    # The collector fails closed without a Git inventory, so the fixture is a checkout.
    system("git", "-C", @root, "init", "-q", "--initial-branch=main", out: File::NULL, err: File::NULL) || raise("git init failed")
    # Ignored as the real checkout ignores them, in .git/info/exclude so no file joins the
    # corpus: the run writes .master/ and runtime/ as it goes, and unignored they changed the
    # exclusion digest after pass 1 and reset the clean streak.
    File.write(File.join(@root, ".git", "info", "exclude"), ".master/\nruntime/\n")
    @bus = FakeBus.new
    # The real baseline runs every check stage; this file asserts what /fix does
    # with a baseline, not how one is measured (test_check_chain.rb owns that).
    @real_baseline = Operator::CheckChain.method(:baseline)
    Operator::CheckChain.define_singleton_method(:baseline) { |**| {} }
  end

  def teardown
    Operator::CheckChain.define_singleton_method(:baseline, @real_baseline)
    @previous_deep_trace.nil? ? ENV.delete("MASTER_FIX_DEEP_TRACE") : ENV["MASTER_FIX_DEEP_TRACE"] = @previous_deep_trace
    FileUtils.remove_entry(@root) if @root && Dir.exist?(@root)
  end

  # Non-matrix tests inject the proof status they need; the focused terminal test
  # selects :not_measured to exercise the production fail-closed contract.
# DONE needs a persisted, read-back, plan-bound four-stream receipt (completion.rb).
# A case about convergence itself supplies one that matches whatever plan the run
# pinned; the cases about withholding DONE build their loop without it.
ProvenPlan = Struct.new(:digest, :manifest) do
  def to_h = manifest
end
PLAN_KEYS = %w[identity_digest scope_digest source_digest law_digest law_source_digest authority_digest
               toolchain_digest exclusion_digest adapter_digest].freeze

def prove(loop)
  unless loop.instance_variable_get(:@fix_plan)
    loop.instance_variable_set(:@fix_plan, ProvenPlan.new("a" * 64, PLAN_KEYS.to_h { |key| [key, "b" * 64] }))
  end
  loop.define_singleton_method(:persist_assessment_receipt) do |**|
    plan = @fix_plan
    { "status" => "persisted", "readback_verified" => true, "matrix_status" => "complete",
      "verification" => "verified", "plan_digest" => plan.digest }.merge(plan.to_h.slice(*PLAN_KEYS))
  end
  loop
end

  def build_loop(violations, ground_truth: nil, council: nil, assessment_matrix_status: :complete)
    loop = Master::Fix::FixLoop.new(
      laws: [StubRule.new("TEST_RULE", :warning)],
      agent: OpenCircuitAgent.new,
      scanner: ConstantScanner.new(violations),
      root: @root, bus: @bus, git: StubGit.new, ground_truth:
    )
    runner = loop.instance_variable_get(:@pass_runner)
    runner.define_singleton_method(:assessment_matrix_status) { assessment_matrix_status }
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

  # /scan is a retired public command. The router may still recognize the old
  # spelling only long enough to rewrite it to /fix, so no separate scan
  # dispatcher, help topic, or pipeline stage can survive.

  def test_convergence_accepts_non_finite_baseline_without_coercion_crash
    discipline = Master::Fix::ConvergenceDiscipline.new(root: @root, bus: @bus)
    discipline.begin_run([File.join(@root, "dummy.yml")])

    assert_equal Master::Fix::ConvergenceDiscipline::UNMEASURED_SCORE, discipline.best_state[:score]
    assert_equal 0.0, discipline.quality_delta
    refute discipline.improving?
  end

  # /fix STUDIO refused every file because dilla.rb was past the line limit. The oversized file is a
  # gap that keeps DONE out of reach; the rest of the corpus is still repaired.
  def test_an_uninspectable_file_blocks_done_but_not_the_repair_of_the_rest
    File.write(File.join(@root, "oversized.rb"), "x" * (Master::Fix::Scan::FileProcessor::MAX_FILE_BYTES + 1))
    loop = prove(build_loop([]))
    repaired = []

    loop.define_singleton_method(:run_journaled) do |journal, files:, **rest|
      repaired.concat(files)
      finish_run(Master::Result.ok("DONE: clean"), rest[:target], journal["id"], **rest.slice(:mission, :requested))
    end

    result = run_unrequested(loop)

    assert_equal [File.join(@root, "dummy.yml")], repaired
    assert_equal :blocked, loop.last_terminal_state, "a corpus with a blocking skip must not be reported as clean"
    assert_match(/\ABLOCKED: finished with gaps, uninspectable inputs remain: too_large=1/, result.value!)
  end

  def run_unrequested(loop)
    result = nil
    Master::Io::LaneSelection.stub(:announce, nil) do
      loop.stub(:outcome_guidance, { incremental: false, prediction: nil }) do
        capture_io { result = loop.run(@root, max_passes: 1, budget_seconds: 60, incremental: false) }
      end
    end
    result
  end

  def test_fix_extends_pass_budget_while_measured_state_improves
    loop = Master::Fix::FixLoop.allocate
    calls = []
    checks = 0
    discipline = Object.new
    discipline.define_singleton_method(:improving?) do
      checks += 1
      checks == 1
    end
    loop.instance_variable_set(:@convergence_discipline, discipline)
    loop.instance_variable_set(:@wishlist, Object.new)
    loop.instance_variable_set(:@root, @root)
    loop.define_singleton_method(:run_one_pass) do |i, **|
      calls << i
      nil
    end

    deadline = Object.new
    deadline.define_singleton_method(:expired?) { false }

    result = loop.send(
      :run_passes,
      files: [],
      target: "/tmp/fix-target",
      max_passes: 2,
      deadline:,
      budget_seconds: 60,
      start_pass: 1,
      run_id: "test-run",
    )

    assert_equal ["PLATEAU: pass limit (5) reached"], [result.value!]
    assert_equal [0, 1, 2, 3, 4], calls
  end

  def test_human_decision_is_a_terminal_pass_outcome
    loop = Master::Fix::FixLoop.allocate
    journal_events = []
    journal = Object.new
    journal.define_singleton_method(:history) { |**| [] }
    journal.define_singleton_method(:crash) { |*| nil }
    journal.define_singleton_method(:pass_start) { |run_id, pass, transaction_id:| journal_events << [:start, run_id, pass, transaction_id] }
    journal.define_singleton_method(:pass_finish) do |run_id, pass, status:, message:|
      journal_events << [:finish, run_id, pass, status, message]
    end
    loop.instance_variable_set(:@run_journal, journal)

    pass_result = Master::Fix::FixLoop::PassRunner::PassResult.new(
      status: :human_decision, consecutive_clean: 0, message: "operator review required"
    )
    runner = Object.new
    runner.define_singleton_method(:run_pass) { |**| pass_result }
    runner.define_singleton_method(:pass_progress?) { false }
    loop.instance_variable_set(:@pass_runner, runner)
    loop.define_singleton_method(:structural_repair?) { |*, **| false }

    deadline = Object.new
    deadline.define_singleton_method(:expired?) { false }
    deadline.define_singleton_method(:at) { Time.now + 60 }

    result = loop.send(
      :run_passes,
      files: [],
      target: @root,
      max_passes: 10,
      deadline:,
      budget_seconds: 60,
      run_id: "human-decision-run",
    )

    assert_match(/\AHUMAN_DECISION: /, result.value!)
    assert_equal 1, journal_events.count { |event| event.first == :start }
    assert_equal [:finish, "human-decision-run", 1, :human_decision, "operator review required"],
                 journal_events.last
  end

  def test_incremental_done_requires_a_full_target_proof
    loop = Master::Fix::FixLoop.allocate
    loop.instance_variable_set(:@root, @root)
    full_files = [File.join(@root, "dummy.yml")]
    second = File.join(@root, "second.rb")
    File.write(second, "puts :second\\n")
    full_files << second

    collector = Object.new
    collector.define_singleton_method(:collect) { |_target| full_files.dup }
    collector.define_singleton_method(:candidate_count) { full_files.size }
    collector.define_singleton_method(:skipped) { 0 }
    collector.define_singleton_method(:blocking_skips) { {} }
    loop.instance_variable_set(:@file_collector, collector)

    observed = []
    discipline = Object.new
    discipline.define_singleton_method(:begin_run) { |files, **_options| observed << files.dup }
    loop.instance_variable_set(:@convergence_discipline, discipline)

    journal = Object.new
    journal.define_singleton_method(:history) { |**| [] }
    journal.define_singleton_method(:crash) { |*| nil }
    journal.define_singleton_method(:history) do |limit:|
      [{ "id" => "run", "passes" => [{ "pass" => 1, "state" => "committed" }] }]
    end
    journal.define_singleton_method(:next_pass) { |_record| 2 }
    loop.instance_variable_set(:@run_journal, journal)

    reachability = Object.new
    reachability.define_singleton_method(:verify!) { |_target, files:| observed << files.dup }
    loop.instance_variable_set(:@reachability, reachability)
    loop.instance_variable_set(:@bus, @bus)

    calls = []
    loop.define_singleton_method(:terminal_state_for) do |result|
      result.value!.start_with?("DONE:") ? :done : :plateau
    end
    loop.define_singleton_method(:run_passes) do |**args|
      calls << args
      Master::Result.ok("DONE: full-scope proof passed")
    end

    deadline = Object.new
    deadline.define_singleton_method(:expired?) { false }
    partial = [File.join(@root, "dummy.yml")]
    result = loop.send(
      :verify_incremental_scope,
      Master::Result.ok("DONE: changed files clean"),
      incremental: true,
      journal: { "id" => "run" },
      target: @root,
      files: partial,
      max_passes: 10,
      deadline:,
      budget_seconds: 60,
      run_id: "run",
    )

    assert_equal "DONE: full-scope proof passed", result.value!
    assert_equal full_files.sort, partial.sort
    assert_equal full_files.sort, calls.fetch(0).fetch(:files).sort
    assert_equal 2, calls.fetch(0).fetch(:start_pass)
    assert_equal 10, calls.fetch(0).fetch(:max_passes)
    assert_equal full_files.sort, observed.fetch(0).sort
  end

  def test_convergence_scores_rendered_and_opportunity_findings_in_same_pass
    seen = []
    discipline = Object.new
    discipline.define_singleton_method(:observe) do |pass:, findings:, files:, progressed:|
      seen << findings
    end
    discipline.observe(
      pass: 1,
      findings: [{ rule: "RENDERED_VISUAL_REFINEMENT" }, { rule: "OPPORTUNITY" }],
      files: [],
      progressed: false,
    )

    assert_equal 2, seen.first.size
  end

  def test_convergence_discipline_reports_measured_improvement
    discipline = Master::Fix::ConvergenceDiscipline.new(root: Dir.mktmpdir("discipline"))
    discipline.begin_run([])
    first = { law: "TEST_RULE", file: "a.rb", line: 1, message: "one", severity: :warning }
    second = { law: "TEST_RULE", file: "b.rb", line: 1, message: "two", severity: :warning }
    discipline.observe(pass: 1, findings: [first, second], files: [], progressed: true)
    discipline.observe(pass: 2, findings: [first], files: [], progressed: false)

    assert discipline.improving?
    assert_equal 0.5, discipline.quality_delta
  end

  def test_progress_without_measured_risk_reduction_is_not_improvement
    discipline = Master::Fix::ConvergenceDiscipline.new(root: @root, bus: @bus)
    discipline.begin_run([File.join(@root, "dummy.yml")])
    finding = {
      law: "TEST_RULE", file: "dummy.yml", line: 1, message: "same finding", severity: :warning
    }

    discipline.observe(pass: 1, findings: [finding], files: [File.join(@root, "dummy.yml")], progressed: true)
    refute discipline.improving?, "a single observation has no measured comparison"

    discipline.observe(pass: 2, findings: [finding], files: [File.join(@root, "dummy.yml")], progressed: true)
    refute discipline.improving?, "unchanged risk is not improvement, even when bytes changed"
  end

  def test_convergence_checkpoint_round_trip_preserves_measured_history
    path = File.join(@root, "dummy.yml")
    discipline = Master::Fix::ConvergenceDiscipline.new(root: @root, bus: @bus)
    discipline.begin_run([path])
    pair = [
      { law: "TEST_RULE", file: "dummy.yml", line: 1, message: "one", severity: :warning },
      { law: "TEST_RULE", file: "dummy.yml", line: 2, message: "two", severity: :warning },
    ]
    discipline.observe(pass: 1, findings: pair, files: [path], progressed: true)
    discipline.observe(pass: 2, findings: pair.first(1), files: [path], progressed: false)
    saved = JSON.parse(JSON.generate(discipline.checkpoint_state))

    resumed = Master::Fix::ConvergenceDiscipline.new(root: @root, bus: @bus)
    resumed.begin_run([path])
    assert resumed.restore_checkpoint(saved)
    assert resumed.improving?
    assert_equal 2, resumed.receipt[:observations]
    assert_equal 0.5, resumed.quality_delta
    assert_equal discipline.checkpoint_state["authority_baseline"], resumed.checkpoint_state["authority_baseline"]
  end

  def test_pass_state_restore_preserves_cycle_detection
    loop = Master::Fix::FixLoop.allocate
    checkpoint = {
      "version" => 1,
      "history" => [3, 2, 1],
      "seen_snapshots" => ["a" * 64, "b" * 64],
      "recurring_violations" => { "same-finding" => 2 },
      "consecutive_clean" => 1,
    }

    state = loop.send(:restore_pass_state, checkpoint)
    assert_equal [3, 2, 1], state[:history]
    assert_equal 2, state[:seen_snapshots].size
    assert_equal 2, state[:recurring_violations]["same-finding"]
    assert_equal 1, state[:consecutive_clean]
  end

  def test_invalid_convergence_checkpoint_is_rejected
    discipline = Master::Fix::ConvergenceDiscipline.new(root: @root, bus: @bus)
    discipline.begin_run([File.join(@root, "dummy.yml")])
    refute discipline.restore_checkpoint({ "version" => 1, "baseline_present" => true,
                                           "authority_baseline" => {}, "critical_baseline" => [],
                                           "history" => [], "observation_count" => 0 })
  end

  def test_run_journal_persists_convergence_checkpoints
    journal = Master::Fix::RunJournal.new(root: @root, bus: @bus)
    run = journal.start_or_resume(target: @root, files: [File.join(@root, "dummy.yml")],
                                  max_passes: 2, budget_seconds: 60)
    journal.save_convergence_state(
      run["id"],
      { "version" => 1, "observations" => 4 },
      pass_state: {
        "version" => 1,
        "history" => [2, 1],
        "seen_snapshots" => ["a" * 64],
        "recurring_violations" => { "finding-a" => 2 },
        "consecutive_clean" => 1,
      },
    )

    saved = journal.history.find { |entry| entry["id"] == run["id"] }
    assert_equal({ "version" => 1, "observations" => 4 }, saved["convergence_state"])
    assert_equal [2, 1], saved.dig("pass_state", "history")
    assert_equal ["a" * 64], saved.dig("pass_state", "seen_snapshots")
  end

  def test_unmeasured_proof_baseline_is_inconclusive_not_green
    pass = Master::CLI::Pipeline::Pass.allocate
    baseline = Master::CLI::Pipeline::Proof::Reading.parse(false, ["proof suite MASTER: FAIL", "LoadError"])

    refute baseline.measured?
    assert_match(/INCONCLUSIVE/, pass.send(:baseline_line, baseline))
  end

  def quiet_runner
    runner = Master::Fix::FixLoop::PassRunner.allocate
    runner.instance_variable_set(:@root, "/tmp")
    runner.instance_variable_set(:@skip_guard, Master::Fix::ScanSkipGuard.new)
    runner.instance_variable_set(:@bus, Object.new.tap do |bus|
      bus.define_singleton_method(:publish) { |_event, _payload = {}| nil }
    end)
    runner
  end

  def test_an_unreadable_file_is_recorded_and_the_pass_carries_on
    runner = quiet_runner
    error = Master::Result.err("file too long: sample.rb", category: :validation)

    assert_equal [], runner.send(:skip_unreadable, "/tmp/sample.rb", error)
    assert runner.gaps?
    assert_equal ["sample.rb"], runner.gaps.fetch(:uninspected).keys
  end

  def test_a_scan_that_raises_costs_that_file_and_not_the_pass
    runner = quiet_runner
    path = File.join(@root, "walk.js")
    File.write(path, "x\n")
    runner.instance_variable_set(:@preflight, Struct.new(:none) { def findings(_paths) = [] }.new)
    runner.instance_variable_set(
      :@scan_phase,
      Struct.new(:none) { def call(_path) = Master::Result.err("scan failed: boom", category: :infrastructure) }.new,
    )
    runner.instance_variable_set(:@root, @root)

    assert_equal [], runner.violations_for(path)
    assert_match(/boom/, runner.gaps.fetch(:uninspected).fetch("walk.js"))
  end

  def test_a_failing_stage_is_recorded_and_the_next_stage_still_runs
    runner = quiet_runner
    ran = []

    first = runner.send(:guarded, :council, 1, :fallback) { raise ArgumentError, "no quorum" }
    second = runner.send(:guarded, :model_fixes, 1) { ran << :model_fixes }

    assert_equal :fallback, first
    assert_equal [:model_fixes], second
    assert_equal [:council], runner.gaps.fetch(:stage_failures).keys
    assert_match(/ArgumentError: no quorum/, runner.gaps.fetch(:stage_failures).fetch(:council).first)
  end

  def test_one_failing_model_stage_does_not_stop_the_wishlist_or_the_run_id_reaching_it
    runner = quiet_runner
    calls = []
    runner.instance_variable_set(:@resource_budget, Struct.new(:none) { def measure = {}; def critical?(_) = false }.new)
    runner.instance_variable_set(:@council, Struct.new(:none) { def run(**) = raise("no lane answered") }.new)
    runner.define_singleton_method(:unremembered) { |found| found }
    runner.define_singleton_method(:files_with_violations) { |_found, files| files }
    runner.define_singleton_method(:run_llm_stage) { |*, **| calls << :model }
    runner.define_singleton_method(:run_wishlist_stage) { |findings, **kw| calls << [:wishlist, findings.size, kw[:run_id]] }
    found = [{ law: "SOME_LAW" }, { law: Master::Fix::Wishlist::LAW_ID }]

    runner.send(:dispatch_llm_stages, found, ["a.rb"], 1, nil, nil, run_id: "run-7")

    assert_equal [:model, [:wishlist, 1, "run-7"]], calls
    assert_equal [:council], runner.gaps.fetch(:stage_failures).keys
  end

  def test_a_run_that_would_be_done_but_had_gaps_ends_blocked_not_done
    loop = build_loop([], assessment_matrix_status: :not_measured)
    runner = loop.instance_variable_get(:@pass_runner)
    done = Master::Result.ok("DONE: all clean")

    matrix_blocked = loop.send(:blocked_by_gaps, done)
    assert_match(
      /\ABLOCKED: finished with gaps, law\/stream\/surface assessment matrix not measured; DONE withheld/,
      matrix_blocked.value!,
    )

    runner.send(:skip_unreadable, File.join(@root, "walk.js"), Master::Result.err("scan failed", category: :infrastructure))
    blocked = loop.send(:blocked_by_gaps, done)

    assert_match(/\ABLOCKED: finished with gaps, 1 file\(s\) not scanned \(walk\.js\)/, blocked.value!)
    assert_includes blocked.value!, "assessment matrix not measured"
    plateau = Master::Result.ok("PLATEAU: no further improvement")
    assert_same plateau, loop.send(:blocked_by_gaps, plateau), "only DONE is downgraded"
  end

def test_manual_fix_upgrades_semantic_scanning_to_full
  scanner = Object.new
  called = false
  scanner.define_singleton_method(:full_semantic!) { called = true; scanner }
  runner = build_loop([]).then { |l| l.instance_variable_get(:@pass_runner) }
  runner.instance_variable_set(:@scan_phase, Master::Fix::ScanPhase.new(scanner:, root: @root))

  runner.full_semantic!

  assert called
end

def test_builder_gives_the_pass_runner_its_scanner_and_violation_tally
  scanner = ConstantScanner.new([])
  loop = Master::Fix::FixLoop.new(
    laws: [StubRule.new("TEST_RULE", :warning)], agent: OpenCircuitAgent.new,
    scanner:, root: @root, bus: @bus, git: StubGit.new
  )
  runner = loop.instance_variable_get(:@pass_runner)

  assert_same scanner, runner.instance_variable_get(:@scanner)
  assert_equal 0, runner.instance_variable_get(:@violation_counts)["TEST_RULE"]
end

  def test_budget_closeout_records_blocked_when_done_is_downgraded_for_gaps
    loop = prove(build_loop([]))
    runner = loop.instance_variable_get(:@pass_runner)
    runner.send(
      :skip_unreadable,
      File.join(@root, "walk.js"),
      Master::Result.err("scan failed", category: :infrastructure),
    )

    journal = Object.new
    journal.define_singleton_method(:history) { |**| [] }
    journal.define_singleton_method(:crash) { |*| nil }
    journal.define_singleton_method(:terminal) { |*| nil }
    loop.instance_variable_set(:@run_journal, journal)
    reasons = []

    Master::Fix::RunBudget.stub(:finish_run, ->(reason: "completed") { reasons << reason }) do
      loop.send(:finish_run, Master::Result.ok("DONE: all clean"), @root, "run-budget-blocked", requested: true)
    end

    assert_equal 1, reasons.size
    assert_match(/\Ablocked: BLOCKED: finished with gaps/, reasons.first)
    refute_equal "completed", reasons.first
  end

  def test_scan_is_not_a_public_command
    assert_includes Master::CLI::TurnRouter::PIPELINE_SLASH, "scan"
    refute_includes Master::CLI::TurnRouter::PIPELINE_COMMANDS, "scan"
    refute Master::CLI::CommandRegistry::HELP_TOPICS.key?("scan")
    refute Master::CLI::CommandRegistry.respond_to?(:dispatch_scan)
    assert_equal "/fix RAILS", Master::CLI::TurnRouter.rewrite_slash("/scan RAILS")
    assert_includes Master::CLI::Pipeline::Pass::STAGES, "fix"
    refute_includes Master::CLI::Pipeline::Pass::STAGES, "scan"
  end

  def test_scoped_fix_does_not_preflight_unrelated_trees
    assert_equal ["RAILS"], Master::CLI::CommandRegistry.execution_trace_scopes("RAILS")
    assert_equal ["RAILS"], Master::CLI::CommandRegistry.execution_trace_scopes("../RAILS")
    assert_equal ["OPENBSD"], Master::CLI::CommandRegistry.execution_trace_scopes("../OPENBSD")
    assert_equal %w[MASTER RAILS], Master::CLI::CommandRegistry.execution_trace_scopes("MASTER RAILS")
    assert_nil Master::CLI::CommandRegistry.execution_trace_scopes("")
  end

  def test_bare_fix_resolves_to_the_current_master_checkout
    resolver = Class.new do
      include Master::CLI::Pipeline::TargetResolver
      def initialize(root) = @root = root
    end.new(Master::ROOT)

    assert_equal Master::ROOT, resolver.resolve_target("")
    assert_equal Master::REPO_ROOT, resolver.resolve_target("everything")
    assert_equal Master::RAILS_ROOT, resolver.resolve_target("RAILS")
  end

  def test_recursive_tree_globs_resolve_to_the_tree_root
    resolver = Class.new do
      include Master::CLI::Pipeline::TargetResolver
      def initialize(root) = @root = root
    end.new(Master::ROOT)

    assert_equal Master::RAILS_ROOT, resolver.resolve_target("RAILS/**")
    assert_equal Master::RAILS_ROOT, resolver.resolve_target("RAILS/**/*")
  end

  def test_master_recursive_tree_globs_resolve_to_the_repo_master_root
    resolver = Class.new do
      include Master::CLI::Pipeline::TargetResolver
      def initialize(root) = @root = root
    end.new(Master::ROOT)

    assert_equal Master::ROOT, resolver.resolve_target("MASTER/**")
    assert_equal Master::ROOT, resolver.resolve_target("MASTER/**/*")
  end

  def test_fix_target_resolver_rejects_paths_outside_governed_trees
    resolver = Class.new do
      include Master::CLI::Pipeline::TargetResolver
      def initialize(root) = @root = root
    end.new(Master::ROOT)

    assert_equal Master::REPO_ROOT, resolver.resolve_target("../")
    assert_raises(ArgumentError) { resolver.resolve_target("../../") }
    # A bare relative name resolves under MASTER/, so the fixture is an absolute
    # path outside every tree that does not exist either.
    assert_raises(ArgumentError) { resolver.resolve_target("/nonexistent/outside_every_tree.md") }
  end

  def test_fix_target_resolver_keeps_existing_governed_files
    resolver = Class.new do
      include Master::CLI::Pipeline::TargetResolver
      def initialize(root) = @root = root
    end.new(Master::ROOT)

    assert_equal Master::ROOT, resolver.resolve_target("MASTER")
    assert_equal File.join(Master::RAILS_ROOT, "brgen"), resolver.resolve_target("RAILS/brgen")
  end

  def test_fix_target_resolver_accepts_master_relative_internal_paths
    resolver = Class.new do
      include Master::CLI::Pipeline::TargetResolver
      def initialize(root) = @root = root
    end.new(Master::ROOT)

    assert_equal File.join(Master::ROOT, "lib", "io"), resolver.resolve_target("lib/io")
  end

  def test_openbsd_recursive_tree_globs_resolve_to_the_tree_root
    resolver = Class.new do
      include Master::CLI::Pipeline::TargetResolver
      def initialize(root) = @root = root
    end.new(Master::ROOT)

    openbsd = File.join(Master::REPO_ROOT, "OPENBSD")
    assert_equal openbsd, resolver.resolve_target("OPENBSD/**")
    assert_equal openbsd, resolver.resolve_target("OPENBSD/**/*")
  end

  def test_all_four_tree_names_resolve_to_the_pub4_root
    resolver = Class.new do
      include Master::CLI::Pipeline::TargetResolver
      def initialize(root) = @root = root
    end.new(Master::ROOT)

    assert_equal Master::REPO_ROOT, resolver.resolve_target("MASTER RAILS OPENBSD STUDIO")
    assert_equal Master::REPO_ROOT, resolver.resolve_target("openbsd, rails, master, studio")
    refute_equal Master::REPO_ROOT, resolver.resolve_target("MASTER RAILS")
  end

  def test_check_chain_recognizes_all_four_tree_names
    assert_equal %w[MASTER RAILS OPENBSD STUDIO],
                 Operator::CheckChain.trees_for_target("MASTER RAILS OPENBSD STUDIO")
    assert_equal %w[MASTER RAILS OPENBSD STUDIO],
                 Operator::CheckChain.trees_for_target("openbsd,rails,master,studio")
  end

  def test_check_chain_resolves_default_and_dot_to_master_only
    assert_equal ["MASTER"], Operator::CheckChain.trees_for_target("")
    assert_equal ["MASTER"], Operator::CheckChain.trees_for_target(".")
    assert_equal ["MASTER"], Operator::CheckChain.trees_for_target("master")
    assert_equal %w[MASTER RAILS OPENBSD STUDIO], Operator::CheckChain.trees_for_target("all")
    assert_equal %w[MASTER RAILS OPENBSD STUDIO], Operator::CheckChain.trees_for_target("everything")
  end

  def test_check_chain_resolves_master_relative_internal_paths
    assert_equal ["MASTER"], Operator::CheckChain.trees_for_target("lib/io")
  end

  def test_studio_recursive_tree_globs_resolve_to_the_tree_root
    resolver = Class.new do
      include Master::CLI::Pipeline::TargetResolver
      def initialize(root) = @root = root
    end.new(Master::ROOT)

    studio = File.join(Master::REPO_ROOT, "STUDIO")
    assert_equal studio, resolver.resolve_target("STUDIO/**")
    assert_equal studio, resolver.resolve_target("STUDIO/**/*")
  end

  def test_scan_request_resolves_all_four_trees_from_repo_root
    {
      "MASTER/lib" => File.join(Master::ROOT, "lib"),
      "RAILS/__shared" => File.join(Master::RAILS_ROOT, "__shared"),
      "OPENBSD/etc" => File.join(Master::REPO_ROOT, "OPENBSD", "etc"),
      "STUDIO/lora" => File.join(Master::REPO_ROOT, "STUDIO", "lora"),
    }.each do |target, expected_root|
      request = Master::CLI::Scan::Request.new(scanner: nil, root: Master::ROOT, arg: target)
      assert_equal expected_root, request.send(:target_arg), target
    end
  end

  def test_check_verification_is_read_only
    seen = []
    result = Operator::CheckChain.stub(
      :report,
      ->(_selected, scan_only:, trees:, return_results:) { seen << { scan_only:, trees:, return_results: }; [0, []] },
    ) do
      Operator::CheckChain.verify_fix(target: "RAILS")
    end

    assert_equal [true], seen.map { |row| row[:scan_only] }
    assert_equal [true], seen.map { |row| row[:return_results] }
    assert_equal ["RAILS"], seen.map { |row| row[:trees] }.first
    assert_equal [0, []], result
  end

  def test_fix_preview_includes_structural_plan_and_order
    loop = build_loop([])
    sweep = Object.new
    sweep.define_singleton_method(:preview) do |target:, run_id:|
      [{ problem_id: "p1", candidate_operations: %w[split simplify], target:, run_id: }]
    end
    loop.instance_variable_set(:@sweeps, [sweep])

    result = loop.preview(@root)

    assert_equal [%w[split simplify]], result.value!.fetch(:structure).map { |row| row.fetch(:candidate_operations) }
    assert_equal Master.law("transformation_policy").fetch("order"), result.value!.fetch(:transformation_order)
  end

  # Every byte of the checkout, .git included (HEAD, refs, index). mtimes are
  # left out on purpose: a read may touch an atime, but no content may change.
  def checkout_digest(root)
    Dir.glob(File.join(root, "**", "*"), File::FNM_DOTMATCH).sort.filter_map do |path|
      next if File.directory?(path)

      [path.delete_prefix(root), Digest::SHA256.file(path).hexdigest]
    end
  end

  def commit_fixture!
    system("git", "-C", @root, "add", "-A", out: File::NULL, err: File::NULL)
    system("git", "-C", @root, "-c", "user.name=t", "-c", "user.email=t@example.test",
           "commit", "-qm", "base", out: File::NULL, err: File::NULL)
  end

  def test_preview_leaves_the_checkout_byte_identical
    File.write(File.join(@root, "tracked.rb"), "puts 1\n")
    commit_fixture!
    File.write(File.join(@root, "untracked.rb"), "puts 2\n")
    loop = build_loop([{ rule: "TEST_RULE", file: File.join(@root, "tracked.rb"), line: 1, message: "x" }])
    before = checkout_digest(@root)

    assert loop.preview(@root).ok?
    assert_equal before, checkout_digest(@root), "preview changed the checkout"
  end

  def test_dry_run_does_not_run_mutating_check_verification
    File.write(File.join(@root, "tracked.rb"), "puts 1\n")
    commit_fixture!
    File.write(File.join(@root, "untracked.rb"), "puts 2\n")
    before = checkout_digest(@root)

    fix_loop = Object.new
    fix_loop.define_singleton_method(:publish_pending!) { flunk("dry-run attempted delivery") }
    fix_loop.define_singleton_method(:run) { |target, **| flunk("dry-run started the repair") }
    fix_loop.define_singleton_method(:preview) { |_| Master::Result.ok(total: 1, laws: { "RULE" => 1 }, files: {}) }
    scanner = Object.new
    def scanner.scan(*) = Master::Result.ok([])
    def scanner.scan_dir(*) = Master::Result.ok([])

    Operator::CheckChain.stub(:verify_fix, ->(**) { flunk("dry-run reached CheckChain.verify_fix") }) do
      Master::CLI::CommandRegistry.stub(:observe, ->(*) { "clean" }) do
        result = Master::CLI::CommandRegistry.dispatch_fix(
          scanner:, fix_loop:, deliberation: nil, root: @root, bus: nil,
          ctx: { args: ". --dry-run --no-aesthetic" }
        )

        assert_includes result, "preview:"
      end
    end

    assert_equal before, checkout_digest(@root), "dispatcher dry-run changed checkout content, .git, index or untracked files"
  end

  def test_dispatch_announces_read_only_mode_before_preflight
    fix_loop = Object.new
    fix_loop.define_singleton_method(:publish_pending!) { flunk("dry-run attempted delivery") }
    fix_loop.define_singleton_method(:run) { |target, **| flunk("dry-run started repair") }
    fix_loop.define_singleton_method(:preview) { |_| Master::Result.ok(total: 0, laws: {}, files: {}) }
    scanner = Object.new
    def scanner.scan(*) = Master::Result.ok([])
    def scanner.scan_dir(*) = Master::Result.ok([])
    events = []

    Master::Trace::Dmesg.stub(
      :status,
      ->(unit, message, **_options) { events << [:status, unit, message] },
    ) do
      Master::CLI::CommandRegistry.stub(
        :observe,
        ->(*) { events << [:observe]; "clean" },
      ) do
        result = Master::CLI::CommandRegistry.dispatch_fix(
          scanner:, fix_loop:, deliberation: nil, root: @root, bus: nil,
          ctx: { args: ". --dry-run --no-aesthetic" },
        )

        assert_includes result, "preview:"
      end
    end

    expected = [:status, "fix0", "mode=read-only target=MASTER boundary=no-write-or-publish"]
    assert_equal expected, events.first
    assert_operator events.index(expected), :<, events.index([:observe]),
                    "the operator must see the execution mode before preflight"
  end

  def test_dispatch_announces_mode_before_target_preflight
    events = []
    expected = [:status, "fix0", "mode=read-only target=MASTER boundary=no-write-or-publish"]

    Master::Trace::Dmesg.stub(
      :status,
      ->(unit, message, **_options) { events << [:status, unit, message] },
    ) do
      Master::CLI::CommandRegistry.stub(
        :fix_targets,
        lambda do |_target, root:|
          assert_equal expected, events.first,
                       "the operator must see mode and write boundary before target preflight"
          raise "preflight sentinel"
        end,
      ) do
        error = assert_raises(RuntimeError) do
          Master::CLI::CommandRegistry.dispatch_fix_parsed(
            scanner: nil, fix_loop: nil, deliberation: nil, root: @root, bus: nil, swarm: nil,
            raw: ". --dry-run", apply: false, critique: true, aesthetic: false, only: nil, target: ".",
          )
        end
        assert_equal "preflight sentinel", error.message
      end
    end

    assert_equal expected, events.first
  end

  def test_bare_fix_routes_to_write_enabled_repair_and_delivery
    previous_trace = ENV["MASTER_FIX_DEEP_TRACE"]
    ENV["MASTER_FIX_DEEP_TRACE"] = "0"

    captured = {}
    fix_loop = Object.new
    fix_loop.define_singleton_method(:publish_pending!) { captured[:published] = true }
    repair = lambda do |_deps, **kwargs|
      captured[:apply] = kwargs.fetch(:apply)
      captured[:target] = kwargs.fetch(:target)
      "repair selected"
    end

    stubs = [
      [Operator::CheckChain, :baseline, {}],
      [Operator::CheckChain, :verify_fix, ->(**) { [0, []] }],
      [Operator::CheckChain, :persist_verified_baselines!, true],
      [Master::CLI::CommandRegistry, :run_pass, repair],
      [Master::Trace::Dmesg, :status, ->(*) {}],
      [Master::Fix::CodeWatch, :requested?, false],
    ]

    stubbed(stubs) do
      result = Master::CLI::CommandRegistry.dispatch_fix_parsed(
        scanner: nil, fix_loop:, deliberation: nil, root: @root, bus: nil, swarm: nil,
        raw: "", apply: nil, critique: nil, aesthetic: false, only: nil, target: "."
      )

      assert_equal "repair selected", result
    end

    assert_equal true, captured[:apply], "bare /fix must not be downgraded to preview"
    assert_equal ".", captured[:target]
    assert captured[:published], "a successful write-enabled pass must reach delivery"
  ensure
    previous_trace ? ENV["MASTER_FIX_DEEP_TRACE"] = previous_trace : ENV.delete("MASTER_FIX_DEEP_TRACE")
  end

  def test_fix_status_target_is_single_line_and_bounded
    label = Master::CLI::CommandRegistry.display_fix_target(
      "RAILS\nfix0: mode=write\t\e[31m"
    )

    refute_match(/[\x00-\x1f\x7f]/, label)
    assert_operator label.length, :<=, 80
    assert_includes label, "RAILS fix0: mode=write"
    assert_equal "MASTER", Master::CLI::CommandRegistry.display_fix_target("\n\t")
    assert_equal "all trees", Master::CLI::CommandRegistry.display_fix_target("EVERYTHING")
  end

  def test_fix_runtime_overrides_are_scoped_to_one_dispatch
    guard = Master::Fix::AutofixGuard
    ledger = Master::Fix::RunLedger
    previous_mode = guard.explicit_mode_override
    previous_limit = ledger.max_files_override
    captured = nil

    Master::CLI::CommandRegistry.stub(
      :run_pass,
      lambda do |_deps, **kwargs|
        captured = { mode: guard.mode, limit: ledger.max_files, kwargs: }
        "selected"
      end,
    ) do
      Master::CLI::CommandRegistry.dispatch_fix(
        scanner: nil, fix_loop: nil, deliberation: nil, root: Master::ROOT, bus: nil,
        ctx: { args: "RAILS --autofix=off --max-files=2 --only critique" }
      )
    end

    assert_equal "off", captured.fetch(:mode)
    assert_equal 2, captured.fetch(:limit)
    assert_equal previous_mode, guard.explicit_mode_override
    assert_equal previous_limit, ledger.max_files_override
  ensure
    guard&.restore_mode_override(previous_mode) if defined?(previous_mode)
    ledger&.restore_max_files_override(previous_limit) if defined?(previous_limit)
  end

  def test_fix_only_flag_reaches_the_selected_stage_without_widening
    captured = nil
    Master::CLI::CommandRegistry.stub(
      :run_pass,
      ->(_deps, **kwargs) { captured = kwargs; "selected" },
    ) do
      Master::CLI::CommandRegistry.dispatch_fix(
        scanner: nil, fix_loop: nil, deliberation: nil, root: Master::ROOT, bus: nil,
        ctx: { args: "RAILS --dry-run --only critique" }
      )
    end

    assert_equal "critique", captured[:only]
    assert_equal false, captured[:apply]
  end

  def test_only_critique_is_read_only_even_with_apply_permission
    captured = nil
    Master::CLI::CommandRegistry.stub(
      :run_pass,
      ->(_deps, **kwargs) { captured = kwargs; "selected" },
    ) do
      Master::CLI::CommandRegistry.dispatch_fix(
        scanner: nil, fix_loop: nil, deliberation: nil, root: Master::ROOT, bus: nil,
        ctx: { args: "RAILS --apply --only critique" }
      )
    end

    assert_equal "critique", captured[:only]
    assert_equal false, captured[:apply]
  end

  def test_named_trees_fix_command_runs_each_tree_in_order_and_preserves_check_scope
    repaired = []
    verified = []
    fix_loop = Object.new
    fix_loop.define_singleton_method(:publish_pending!) { :nothing_to_publish }
    fix_loop.define_singleton_method(:run) { |target, **| repaired << target; Master::Result.ok("DONE: clean") }
    fix_loop.define_singleton_method(:preview) { |_| Master::Result.ok(total: 0, laws: {}, files: {}) }
    scanner = Object.new
    def scanner.scan(*) = Master::Result.ok([])
    def scanner.scan_dir(*) = Master::Result.ok([])

    Operator::CheckChain.stub(:verify_fix, ->(target:, baseline: nil) { verified << target; [0, []] }) do
      Master::CLI::CommandRegistry.stub(:observe, ->(*) { "clean" }) do
        Master::CLI::CommandRegistry.dispatch_fix(
          scanner:, fix_loop:, deliberation: nil, root: Master::ROOT, bus: nil,
          ctx: { args: "MASTER RAILS OPENBSD --no-aesthetic --no-critique" }
        )
      end
    end

    # Named trees run one at a time in the order typed, each proved on its own.
    assert_equal %w[MASTER RAILS OPENBSD].map { |tree| File.join(Master::REPO_ROOT, tree) }, repaired
    assert_equal repaired, verified
  end

  # Commits stay local while the run works; the one push comes after every tree
  # has verified, however many trees were named.
  def test_a_multi_tree_fix_publishes_once_after_all_trees_verify
    events = []
    fix_loop = Object.new
    fix_loop.define_singleton_method(:publish_pending!) { events << :publish }
    fix_loop.define_singleton_method(:run) { |target, **| events << [:repair, File.basename(target)]; Master::Result.ok("DONE: clean") }
    fix_loop.define_singleton_method(:preview) { |_| Master::Result.ok(total: 0, laws: {}, files: {}) }
    scanner = Object.new
    def scanner.scan(*) = Master::Result.ok([])
    def scanner.scan_dir(*) = Master::Result.ok([])

    Operator::CheckChain.stub(:verify_fix, ->(target:, baseline: nil) { events << [:verify, File.basename(target)]; [0, []] }) do
      Master::CLI::CommandRegistry.stub(:observe, ->(*) { "clean" }) do
        Master::CLI::CommandRegistry.dispatch_fix(
          scanner:, fix_loop:, deliberation: nil, root: Master::ROOT, bus: nil,
          ctx: { args: "MASTER RAILS --no-aesthetic --no-critique" }
        )
      end
    end

    assert_equal 1, events.count(:publish)
    assert_equal :publish, events.last
    assert_equal [[:verify, "MASTER"], [:verify, "RAILS"]], events.grep(Array).select { |e| e.first == :verify }
  end

  def test_final_push_failure_is_delivery_failed_and_does_not_persist_baselines
    fix_loop = Object.new
    fix_loop.define_singleton_method(:publish_pending!) { raise IOError, "push token should not appear in the report" }

    result = nil
    no_cache = ->(*) { flunk("failed publish must not cache a delivered baseline") }
    stubs = [
      [Master::CLI::CommandRegistry, :run_pass, ->(_deps, **_kwargs) { "DONE: clean" }],
      [Operator::CheckChain, :baseline, ->(target:) { {} }],
      [Operator::CheckChain, :verify_fix, ->(target:, baseline:) { [0, []] }],
      [Operator::CheckChain, :persist_verified_baselines!, no_cache],
      [Operator::CheckChain, :clear_verified_fix_snapshots!, nil],
    ]

    stubbed(stubs) do
      result = Master::CLI::CommandRegistry.dispatch_fix(
        scanner: nil, fix_loop:, deliberation: nil, root: Master::ROOT, bus: @bus,
        ctx: { args: "MASTER RAILS --no-aesthetic --no-critique" }
      )
    end

    assert_instance_of Master::Result::Err, result
    assert_equal :delivery_failed, result.category
    assert_match(/\ADELIVERY_FAILED: final publish failed after verification \(IOError\)\z/, result.message)
    refute_includes result.message, "push token"
  end

  def test_fix_does_not_start_repair_when_read_only_baseline_mutates
    fix_loop = Object.new
    fix_loop.define_singleton_method(:run) { |*| flunk("repair must not start after the proof changed the checkout") }

    result = nil
    Operator::CheckChain.stub(:baseline_scope_key, ->(*) { "RAILS" }) do
      Operator::CheckChain.stub(
        :baseline,
        ->(**) { raise Operator::CheckChain::BaselineMutation, "read-only pre-repair proof changed 1 path: MASTER/lib/changed.rb" },
      ) do
        result = Master::CLI::CommandRegistry.run_fix_target(
          scanner: Object.new, fix_loop:, root: Master::ROOT, deliberation: nil, bus: nil, swarm: nil,
          target: "RAILS", writes_requested: true, effective_critique: false, critique: false,
          aesthetic: false, only: "fix",
        )
      end
    end

    assert_instance_of Master::Result::Err, result
    assert_equal :validation, result.category
    assert_match(/pre-repair proof blocked/, result.message)
    assert_includes result.message, "MASTER/lib/changed.rb"
  end

  def test_fix_reenters_after_check_repairs_until_the_tree_stabilises
    verified = []
    states = [[0, ["RAILS/app/models/item.rb"]], [0, []]]
    fix_loop = Object.new
    fix_loop.define_singleton_method(:publish_pending!) { :nothing_to_publish }
    fix_loop.define_singleton_method(:run) { |target, **| Master::Result.ok("DONE: clean") }
    fix_loop.define_singleton_method(:preview) { |_| Master::Result.ok(total: 0, laws: {}, files: {}) }
    scanner = Object.new
    def scanner.scan(*) = Master::Result.ok([])
    def scanner.scan_dir(*) = Master::Result.ok([])

    result = Operator::CheckChain.stub(:verify_fix, ->(target:, baseline: nil) { verified << target; states.shift }) do
      Master::CLI::CommandRegistry.stub(:observe, ->(*) { "clean" }) do
        Master::CLI::CommandRegistry.dispatch_fix(
          scanner:, fix_loop:, deliberation: nil, root: Master::ROOT, bus: nil,
          ctx: { args: "RAILS --no-aesthetic --no-critique" }
        )
      end
    end

    assert_equal 2, verified.size
    assert_equal "RAILS", verified.first
    assert_includes result, "DONE: clean"
  end

  def test_critique_stage_calls_council_directly_without_reentering_pipeline
    captured = nil
    fix_loop = Object.new
    fix_loop.define_singleton_method(:publish_pending!) { :nothing_to_publish }
    scanner = Object.new
    deliberation = Object.new
    bus = Object.new

    Master::CLI::CommandRegistry.stub(
      :dispatch_critique,
      ->(**) { raise "critique stage recursively re-entered dispatch_critique" },
    ) do
      Master::CLI::CouncilCrit.stub(
        :run,
        lambda do |root:, deliberation:, bus:|
          captured = { root:, deliberation:, bus: }
          Master::Result.ok("critique: ok")
        end,
      ) do
        pass = Master::CLI::Pipeline::Pass.new(
          scanner:,
          fix_loop:,
          root: Master::ROOT,
          deliberation:,
          bus:,
        )
        assert_equal "critique: ok", pass.send(:deliberation_critique, Master::ROOT)
      end
    end

    assert_equal Master::ROOT, captured[:root]
    assert_equal deliberation, captured[:deliberation]
    assert_equal bus, captured[:bus]
  end

  def test_fix_reports_execution_trace_failure_as_validation_error
    trace_result = Struct.new(:clean?, :summary, :failures).new(
      false,
      "execution_trace: failed",
      ["MASTER/test/broken.rb: syntax failed: Prism::ParseError"],
    )
    fake_trace = Object.new
    fake_trace.define_singleton_method(:run) { trace_result }

    fix_loop = Object.new
    fix_loop.define_singleton_method(:publish_pending!) { :nothing_to_publish }
    fix_loop.define_singleton_method(:run) { |target, **| flunk("repair started after failed preflight") }
    scanner = Object.new
    scanner.define_singleton_method(:scan) { |*| Master::Result.ok([]) }
    scanner.define_singleton_method(:scan_dir) { |*| Master::Result.ok([]) }

    saved = ENV.delete("MASTER_FIX_DEEP_TRACE")
    result = Master::Fix::ExecutionTrace.stub(:new, ->(**) { fake_trace }) do
      Master::CLI::CommandRegistry.dispatch_fix(
        scanner:, fix_loop:, deliberation: nil, root: Master::ROOT, bus: nil,
        ctx: { args: "RAILS --no-aesthetic --no-critique" }
      )
    end

    assert_instance_of Master::Result::Err, result
    assert_equal :validation, result.category
    assert_includes result.message, "execution trace failed"
  ensure
    ENV["MASTER_FIX_DEEP_TRACE"] = saved if saved
  end

  def test_fix_runs_deep_execution_trace_before_repair
    order = []
    fake_trace = Object.new
    fake_trace.define_singleton_method(:run) do
      order << :trace
      Struct.new(:clean?, :summary, :failures).new(true, "execution_trace: clean", [])
    end

    fix_loop = Object.new
    fix_loop.define_singleton_method(:publish_pending!) { :nothing_to_publish }
    fix_loop.define_singleton_method(:run) do |target, **|
      order << :repair
      Master::Result.ok("DONE: clean")
    end
    scanner = Object.new
    scanner.define_singleton_method(:scan) { |*| Master::Result.ok([]) }
    scanner.define_singleton_method(:scan_dir) { |*| Master::Result.ok([]) }

    saved = ENV.delete("MASTER_FIX_DEEP_TRACE")
    result = Master::Fix::ExecutionTrace.stub(:new, ->(**) { fake_trace }) do
      Operator::CheckChain.stub(:verify_fix, ->(**) { [0, []] }) do
        Master::CLI::CommandRegistry.stub(:observe, ->(*) { "clean" }) do
          Master::CLI::CommandRegistry.dispatch_fix(
            scanner:, fix_loop:, deliberation: nil, root: Master::ROOT, bus: nil,
            ctx: { args: "RAILS --no-aesthetic --no-critique" }
          )
        end
      end
    end

    assert_equal [:trace, :repair], order
    assert_includes result, "DONE: clean"
  ensure
    ENV["MASTER_FIX_DEEP_TRACE"] = saved if saved
  end

  # Applies each [owner, method, value] stub in turn around the block, so a test does not nest them.
  def stubbed(stubs, &block)
    return block.call if stubs.empty?

    (owner, name, value), *rest = stubs
    owner.stub(name, value) { stubbed(rest, &block) }
  end

  def test_proof_resolves_the_foreign_operator_namespace
    pass = Master::CLI::Pipeline::Pass.allocate
    name, runner = pass.proof_runner(Master::ROOT)

    assert_equal "MASTER", name
    assert_respond_to runner, :call
  end

  # A file or directory inside a tree proves with the tests that map to it; only the tree
  # itself runs the whole suites. One file once took the full thirty-minute suite per pass.
  def test_a_narrower_target_proves_with_its_own_tests_not_the_whole_suite
    pass = Master::CLI::Pipeline::Pass.allocate
    target = File.join(Master::ROOT, "lib", "cli", "fold_risk.rb")
    ran = []
    Operator::CheckChain.stub(:capture, ->(*cmd, **) { ran << cmd; [true, ["ok"], 0] }) do
      name, runner = pass.proof_runner(target)
      ok, = runner.call

      assert_equal "MASTER tests for fold_risk.rb", name
      assert ok
    end

    assert_equal 1, ran.size
    assert_equal ["test", target], ran.first.last(2)
    refute_includes ran.first.join(" "), "--profile=ci", "the whole suite is not run for one file"
  end

  def test_a_target_no_test_maps_to_is_not_a_failed_repair
    pass = Master::CLI::Pipeline::Pass.allocate
    Operator::CheckChain.stub(:capture, ->(*_cmd, **) { [false, ["test0: failed, no suite maps to lib/x.rb"], 1] }) do
      _name, runner = pass.proof_runner(File.join(Master::ROOT, "lib", "x.rb"))
      ok, = runner.call

      assert ok
    end
  end

def test_a_named_stage_list_without_source_leaves_rails_with_no_proof_runner
  pass = Master::CLI::Pipeline::Pass.allocate
  rails = File.join(Master::RAILS_ROOT, "brgen_dating")
  previous = ENV.delete("MASTER_FIX_CHECK_STAGES")

  assert_equal "rails checks", pass.proof_runner(rails).first

  ENV["MASTER_FIX_CHECK_STAGES"] = "lexical,sprawl"

  assert_nil pass.proof_runner(rails)
  assert_equal "MASTER", pass.proof_runner(Master::ROOT).first

  ENV["MASTER_FIX_CHECK_STAGES"] = "source"

  assert_equal "rails checks", pass.proof_runner(rails).first
ensure
  previous ? ENV["MASTER_FIX_CHECK_STAGES"] = previous : ENV.delete("MASTER_FIX_CHECK_STAGES")
end

  def test_fix_wraps_the_full_lifecycle_in_trace_verbosity
    levels = []
    fix_loop = Object.new
    fix_loop.define_singleton_method(:publish_pending!) { :nothing_to_publish }
    fix_loop.define_singleton_method(:run) { |target, **| Master::Result.ok("DONE: clean") }
    scanner = Object.new
    def scanner.scan(*) = Master::Result.ok([])
    def scanner.scan_dir(*) = Master::Result.ok([])

    Master::Trace::Dmesg.stub(:with_verbosity, ->(level, &block) { levels << level; block.call }) do
      Operator::CheckChain.stub(:verify_fix, ->(target:, baseline: nil) { [0, []] }) do
        Master::CLI::CommandRegistry.stub(:observe, ->(*) { "clean" }) do
          Master::CLI::CommandRegistry.dispatch_fix(
            scanner:, fix_loop:, deliberation: nil, root: Master::ROOT, bus: nil,
            ctx: { args: "RAILS --no-aesthetic --no-critique" }
          )
        end
      end
    end

    # The mode line and the lifecycle are each wrapped, so the level repeats; it is always trace.
    assert_equal ["trace"], levels.uniq
  end

  def test_fix_surfaces_a_check_failure_when_it_makes_no_changes
    fix_loop = Object.new
    fix_loop.define_singleton_method(:publish_pending!) { :nothing_to_publish }
    fix_loop.define_singleton_method(:run) { |target, **| Master::Result.ok("DONE: clean") }
    scanner = Object.new
    def scanner.scan(*) = Master::Result.ok([])
    def scanner.scan_dir(*) = Master::Result.ok([])

    result = Operator::CheckChain.stub(:verify_fix, ->(target:, baseline: nil) { [1, []] }) do
      Master::CLI::CommandRegistry.stub(:observe, ->(*) { "clean" }) do
        Master::CLI::CommandRegistry.dispatch_fix(
          scanner:, fix_loop:, deliberation: nil, root: Master::ROOT, bus: nil,
          ctx: { args: "RAILS --no-aesthetic --no-critique" }
        )
      end
    end

    assert_instance_of Master::Result::Err, result
    assert_equal :validation, result.category
    assert_equal "check verification did not pass (status 1)", result.message
  end

  # 2-4. /fix observes, repairs what the reading found, and observes again.
  def test_fix_observes_repairs_and_observes_again
    seen = []
    repaired = []
    fix_loop = Object.new
    fix_loop.define_singleton_method(:publish_pending!) { :nothing_to_publish }
    fix_loop.define_singleton_method(:run) { |target, **| repaired << target; Master::Result.ok("DONE: clean") }
    fix_loop.define_singleton_method(:preview) { |_| Master::Result.ok(total: 0, laws: {}, files: {}) }
    scanner = Object.new
    def scanner.scan(*) = Master::Result.ok([])
    def scanner.scan_dir(*) = Master::Result.ok([])

    # The proof after a writing pass is MASTER's whole suite, which holds this
    # test; stubbed, so the test measures the pass rather than the suite.
    suites = ->(*) { [true, ["suites: 1/1 green"], 0] }
    # verify_fix would run the real check stages in a subprocess; this test is about the pass.
    out = Operator::CheckChain.stub(:verify_fix, ->(**) { [0, []] }) do
      Operator::CheckChain.stub(:suites, suites) do
        Master::CLI::CommandRegistry.stub(:observe, ->(*, **kw) { seen << kw[:ctx][:args]; "clean" }) do
          Master::CLI::CommandRegistry.dispatch_fix(
            scanner:, fix_loop:, deliberation: nil, root: Master::ROOT, bus: nil,
            ctx: { args: "lib/io --no-aesthetic --no-critique" }
          )
        end
      end
    end

    assert_equal 2, seen.size, "a fix observes before and after the repair"
    assert_equal 1, repaired.size, "the repair runs between the two readings"
    assert_match(/^obs0 at review0: observe$/, out.lines.map(&:chomp).join("\n"))
    assert_match(/^obs1 at review0: re-observe$/, out.lines.map(&:chomp).join("\n"))
  end

  # A suite run as a proof holds tests that run /fix; their proof must not
  # start the suites again, or each level spawns the next without end.
  def test_a_proof_started_inside_a_proof_is_skipped
    pass = Master::CLI::Pipeline::Pass.allocate
    ran = false
    saved = ENV["MASTER_IN_PROOF"]
    ENV["MASTER_IN_PROOF"] = "1"
    name, body = Operator::CheckChain.stub(:suites, ->(*) { ran = true; [true, [], 0] }) do
      pass.send(:proof_section, Master::ROOT)
    end

    assert_equal "proof", name
    assert_match(/already inside a proof run/, body) # source-assertion: ok — the section proof_section returned
    refute ran, "the nested proof ran the suites"
  ensure
    ENV["MASTER_IN_PROOF"] = saved
  end

  # Contribution checks may remain inconclusive outside /fix, but a proof that
  # measured nothing cannot certify the repaired tree. The proof owns strictness
  # for its duration and restores the environment afterwards.
  def test_rails_proof_blocks_inconclusive_measurements_inside_a_proof
    pass = Master::CLI::Pipeline::Pass.allocate
    _name, runner = pass.proof_runner(Master::RAILS_ROOT)
    previous_strict = ENV["CHECK_STRICT_INCONCLUSIVE"]
    # test_helper.rb sets MASTER_IN_PROOF for the whole suite; the ordinary
    # call below must run outside a proof, so the flag is lifted for this test.
    previous_proof = ENV.delete("MASTER_IN_PROOF")
    ENV.delete("CHECK_STRICT_INCONCLUSIVE")
    strict_calls = []
    inconclusive = lambda do |strict_inconclusive: false, **|
      strict_calls << strict_inconclusive
      [false, ["deploy_drift measured nothing"], 3]
    end

    ok, out = Operator::CheckChain.stub(:rails_checks, inconclusive) { runner.call }
    assert ok, "ordinary contribution mode should preserve its inconclusive policy"
    assert_match(/CHECK_STRICT_INCONCLUSIVE/, out.last)

    ok, out = pass.send(:inside_proof) do
      Operator::CheckChain.stub(:rails_checks, inconclusive) { runner.call }
    end
    refute ok, "an inconclusive check passed a proof"
    assert_match(/forbids passing/, out.last)
    assert_equal [false, true], strict_calls, "the proof did not request strict child-check handling"
    assert_nil ENV["CHECK_STRICT_INCONCLUSIVE"], "the proof did not restore its strictness override"

    failed = ->(**) { [false, ["port_inventory failed"], 1] }
    ok, = Operator::CheckChain.stub(:rails_checks, failed) { runner.call }
    refute ok, "a failed check passed the proof"
  ensure
    previous_strict.nil? ? ENV.delete("CHECK_STRICT_INCONCLUSIVE") : ENV["CHECK_STRICT_INCONCLUSIVE"] = previous_strict
    ENV["MASTER_IN_PROOF"] = previous_proof if previous_proof
  end

  def test_rails_checks_launches_a_runner_that_exists
    seen = nil
    capture = ->(*cmd, **) { seen = cmd; [true, [], 0] }
    Operator::CheckChain.stub(:capture, capture) { Operator::CheckChain.rails_checks(scan_only: true) }

    script = seen.map(&:to_s).find { |arg| arg.end_with?("runner.rb") }
    refute_nil script, "rails_checks launched no runner.rb"
    assert File.file?(script), "rails_checks launches #{script}, which does not exist"
  end

  def test_rails_fix_verification_runs_premerge_after_the_repair_aware_runner
    calls = []
    capture = ->(*cmd, chdir: nil, env: {}, **) {
      calls << { cmd:, chdir:, env: }
      [true, ["ok"], 0]
    }

    Operator::CheckChain.stub(:capture, capture) do
      ok, _body, status = Operator::CheckChain.rails_verification(scan_only: true)
      assert ok
      assert_equal 0, status
    end

    assert_equal 2, calls.size
    assert calls.first[:cmd].any? { |arg| arg.to_s.end_with?("runner.rb") }
    assert calls.last[:cmd].any? { |arg| arg.to_s.end_with?("MASTER/tools/rails/premerge.rb") }
    assert_equal File.join(Master::REPO_ROOT, "RAILS"), calls.last[:chdir]
    assert_equal "1", calls.last[:env]["MASTER_FIX_VERIFY"]
  end

  def test_rails_source_stage_uses_the_full_verification_path
    stage = Operator::CheckChain.stages(scan_only: true, trees: ["RAILS"])
                         .find { |candidate| candidate.name == "source" }
    refute_nil stage
    seen = nil

    Operator::CheckChain.stub(:rails_verification, ->(**args) { seen = args; [true, [], 0] }) do
      ok, _body, status = stage.run.call
      assert ok
      assert_equal 0, status
    end

    assert_equal({ scan_only: true }, seen)
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
  def test_preflight_runs_before_scanner_and_can_stop_parser_cascades
    path = File.join(@root, "broken.rb")
    File.write(path, "def broken(\n")

    scanner_called = false
    scanner = Object.new
    scanner.define_singleton_method(:scan) { |*| scanner_called = true; raise "scanner should not run" }

    preflight = Master::Fix::Preflight.new(root: @root)
    loop = Master::Fix::FixLoop.new(
      laws: [StubRule.new("TEST_RULE", :warning)],
      agent: OpenCircuitAgent.new,
      scanner:,
      root: @root,
      bus: @bus,
      git: StubGit.new,
    )
    runner = loop.instance_variable_get(:@pass_runner)
    runner.instance_variable_set(:@preflight, preflight)

    violations = runner.send(:violations_for, path)

    assert_equal "PREFLIGHT", violations.first[:law]
    refute scanner_called
  end

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
      { feedback: [{ feedback: "the name hides the intent" }], cherry_picks: ["rename the flag to what it checks"] }
    end
    loop = build_loop([{ rule: "TEST_RULE", file: File.join(@root, "dummy.yml"), line: 1, message: "x" }],
                      council:)
    runner = loop.instance_variable_get(:@pass_runner)

    loop.run(@root, max_passes: 1)

    refute_empty asked, "the council never ran inside the pass"
    preamble = runner.send(:council_preamble, { cherry_picks: ["rename the flag to what it checks"] })
    assert_includes preamble, "rename the flag to what it checks"
    assert_nil runner.send(:council_preamble, { cherry_picks: [] })
  end

  def test_fix_council_uses_hard_review_briefing
    round = Master::Fix::FixLoop::CouncilRound.new(agent: nil, root: @root, bus: @bus)
    briefing = round.send(:hard_briefing, [File.join(@root, "dummy.yml")])

    assert_includes briefing, "hard critique"
    assert_includes briefing, "authority"
    assert_includes briefing, "bypasses"
    assert_includes briefing, "verification"
    assert_includes briefing, "inversion"
    assert_includes briefing, "dummy.yml"
  end

  def test_hard_review_disable_is_runtime_safe
    previous = ENV["MASTER_FIX_HARD_CRITIQUE"]
    ENV["MASTER_FIX_HARD_CRITIQUE"] = "0"
    round = Master::Fix::FixLoop::CouncilRound.new(agent: nil, root: @root, bus: @bus)

    result = round.send(:critique, [File.join(@root, "dummy.yml")])

    assert_predicate result, :ok?
    assert_equal [], result.value![:cherry_picks]
  ensure
    previous.nil? ? ENV.delete("MASTER_FIX_HARD_CRITIQUE") : ENV["MASTER_FIX_HARD_CRITIQUE"] = previous
  end

  def test_council_result_is_passed_into_the_repair_stage
    findings = { feedback: [], cherry_picks: ["dummy.yml line 1: tighten the boundary"] }
    council = Object.new
    council.define_singleton_method(:run) { |files:, pass:, deadline:| findings }
    loop = build_loop(
      [{ rule: "TEST_RULE", file: File.join(@root, "dummy.yml"), line: 1, message: "x" }],
      council:,
    )
    runner = loop.instance_variable_get(:@pass_runner)
    received = nil
    runner.define_singleton_method(:run_llm_stage) do |found, files, pass, deadline, council:|
      received = council
      0
    end

    runner.send(
      :dispatch_llm_stages,
      [{ rule: "TEST_RULE", file: File.join(@root, "dummy.yml"), line: 1, message: "x" }],
      [File.join(@root, "dummy.yml")],
      1,
      Time.now + 60,
      nil,
    )

    assert_equal findings, received, "council findings must reach the repair stage as repair context"
  end

  def test_finish_run_publishes_machine_readable_repair_outcome
    loop = prove(build_loop([]))
    journal = Object.new
    journal.define_singleton_method(:history) { |**| [] }
    journal.define_singleton_method(:crash) { |*| nil }
    journal.define_singleton_method(:terminal) { |*| nil }
    loop.instance_variable_set(:@run_journal, journal)

    loop.send(:finish_run, Master::Result.ok("DONE: clean"), @root, "run-123", requested: true)
    event = @bus.events.find { |row| row[:event] == "fix_loop:terminal" }

    refute_nil event
    assert_equal "run-123", event[:payload][:task_id]
    assert_equal "code_repair", event[:payload][:capability]
    assert_equal true, event[:payload][:ok]
    assert_equal :done, event[:payload][:state]
  end

  def test_expired_resumed_mission_publishes_timeout_terminal
    commit_fixture!
    loop = build_loop([])
    terminal_rows = []
    journal = Object.new
    journal.define_singleton_method(:history) { |**| [] }
    journal.define_singleton_method(:crash) { |*| nil }
    opened = []
    journal.define_singleton_method(:start_or_resume) do |**|
      opened << (opened.empty? ? "run-timeout" : "run-fresh")
      { "id" => opened.last, "remaining_seconds" => 0.0 }
    end
    journal.define_singleton_method(:active_pass) { |_run| nil }
    journal.define_singleton_method(:terminal) do |run_id, state, message:, evidence: nil|
      terminal_rows << { run_id:, state:, message:, evidence: }
    end
    loop.instance_variable_set(:@run_journal, journal)

    deferred = []
    mission = Object.new
    mission.define_singleton_method(:defer!) { |reason:| deferred << reason }
    mission.define_singleton_method(:requeue_if_requested!) { false }

    Master::Fix::RunBudget.stub(:finish_run, ->(**) {}) do
      Master::Io::LaneSelection.stub(:announce, nil) do
        loop.stub(:outcome_guidance, { incremental: false, prediction: nil }) do
          loop.stub(:mission_for, mission) do
            result = loop.run_unlocked(
              @root, max_passes: 1, budget_seconds: 60, incremental: false, requested: false,
            )

            assert result.err?
            assert_equal :timeout, result.category
          end
        end
      end
    end

    # The expired run is closed and a fresh one opened; this fixture's journal
    # hands back no budget for the fresh run either, so it ends there.
    assert_equal %w[run-timeout run-fresh], opened
    assert_equal %w[run-timeout run-fresh], terminal_rows.map { |row| row[:run_id] }
    assert_equal :timeout, terminal_rows.first[:state]
    assert_match(/budget exhausted before resume/, terminal_rows.first[:message])
    assert_equal 2, deferred.size
    assert_match(/attempt timeout:/, deferred.first)

    event = @bus.events.find { |row| row[:event] == "fix_loop:terminal" }
    refute_nil event, "an expired resumed run needs the canonical terminal event"
    assert_equal :timeout, event[:payload][:state]
  end

  def test_expired_run_recovers_a_persisted_transaction_before_timeout
    commit_fixture!
    loop = build_loop([])
    terminal_rows = []
    journal = Object.new
    journal.define_singleton_method(:history) { |**| [] }
    journal.define_singleton_method(:crash) { |*| nil }
    journal.define_singleton_method(:start_or_resume) do |**|
      { "id" => "run-stranded", "remaining_seconds" => 0.0 }
    end
    journal.define_singleton_method(:active_pass) do |_run|
      { "transaction_id" => "tx-stranded", "pass" => 1 }
    end
    journal.define_singleton_method(:next_pass) { |_run| 2 }
    journal.define_singleton_method(:terminal) do |run_id, state, message:, evidence: nil|
      terminal_rows << { run_id:, state:, message:, evidence: }
    end
    loop.instance_variable_set(:@run_journal, journal)

    recovered_calls = []
    mission = Object.new
    mission.define_singleton_method(:defer!) { |reason:| nil }
    mission.define_singleton_method(:requeue_if_requested!) { false }

    Master::Fix::Transaction::Recovery.stub(:persisted?, true) do
      loop.stub(:resume_active_transaction, lambda { |journal:, run_id:, start_pass:|
        recovered_calls << [run_id, start_pass]
        Master::Result.ok(start_pass)
      }) do
        Master::Fix::RunBudget.stub(:finish_run, ->(**) {}) do
          Master::Io::LaneSelection.stub(:announce, nil) do
            loop.stub(:outcome_guidance, { incremental: false, prediction: nil }) do
              loop.stub(:mission_for, mission) do
                result = loop.run_unlocked(
                  @root, max_passes: 1, budget_seconds: 60,
                  incremental: false, requested: false,
                )
                assert result.err?
                assert_equal :timeout, result.category
              end
            end
          end
        end
      end
    end

    assert_equal [["run-stranded", 2]], recovered_calls
    assert_equal :timeout, terminal_rows.first[:state]
  end


  # The journaled half of a run, callable from a test.
  class JournaledLoop < Master::Fix::FixLoop
    public :run_journaled
  end

  # A journal that records its terminal rows and starts every run at pass 1.
  class TerminalJournal
    attr_reader :rows

    def initialize = @rows = []
    def next_pass(_run) = 1
    def terminal(run_id, state, message:, evidence: nil) = @rows << { run_id:, state:, message:, evidence: }
    def history(**) = []
    def crash(*) = nil
  end

  class PassingReachability
    def verify!(*, **) = true
  end

  def journaled_loop(journal)
    Master::Fix::RunJournal.stub(:new, journal) do
      Master::Fix::Reachability.stub(:new, PassingReachability.new) do
        JournaledLoop.new(laws: [StubRule.new("TEST_RULE", :warning)], agent: OpenCircuitAgent.new,
                          scanner: ConstantScanner.new([]), root: @root, bus: @bus, git: StubGit.new)
      end
    end
  end

  JOURNALED = { files: [], max_passes: 1, budget_seconds: 60, mission: nil, requested: false,
                incremental: false }.freeze

  def run_journal_at(loop, elapsed:, journal_row:)
    budget = Master::Fix::RunBudget
    loop.define_singleton_method(:resume_active_transaction) { |**| Master::Result.ok(1) }

    budget.stub(:elapsed_seconds, elapsed) do
      budget.stub(:finish_run, ->(**) {}) { loop.run_journaled(journal_row, target: @root, **JOURNALED) }
    end
  end

  # The RAILS run of 2026-10-23 crashed "deadline must be positive" when the stages before its
  # first pass had spent the budget. Spent is a timeout the run reports, before any pass.
  def test_a_budget_spent_before_the_first_pass_ends_as_a_timeout_not_a_crash
    journal = TerminalJournal.new
    loop = journaled_loop(journal)
    row = { "id" => "run-spent", "remaining_seconds" => 60.0, "resumed" => false, "budget_clock_at" => 0.0 }

    result = nil
    capture_io { result = run_journal_at(loop, elapsed: 120.0, journal_row: row) }

    assert_equal :timeout, result.category
    assert_match(/spent before pass 1 began/, result.message)
    assert_equal [:timeout], journal.rows.map { |entry| entry[:state] }
  end

  # The command's baseline and first reading ran before the journal opened; they are not the passes'.
  def test_time_spent_before_the_journal_opened_is_not_taken_from_the_passes
    loop = journaled_loop(TerminalJournal.new)
    deadlines = []
    loop.define_singleton_method(:run_passes) do |deadline:, **|
      deadlines << deadline.remaining
      Master::Result.err("stopped", category: :timeout)
    end
    row = { "id" => "run-late", "remaining_seconds" => 60.0, "resumed" => false, "budget_clock_at" => 1800.0 }

    capture_io { run_journal_at(loop, elapsed: 1830.0, journal_row: row) }

    assert_equal 1, deadlines.size
    assert_in_delta 30.0, deadlines.first, 2.0
  end

  def test_failed_resume_recovery_publishes_terminal_and_finishes_budget
    loop = build_loop([])
    terminal_rows = []
    journal = Object.new
    journal.define_singleton_method(:history) { |**| [] }
    journal.define_singleton_method(:crash) { |*| nil }
    journal.define_singleton_method(:next_pass) { |_| 1 }
    journal.define_singleton_method(:terminal) do |run_id, state, message:, evidence: nil|
      terminal_rows << { run_id:, state:, message:, evidence: }
    end
    loop.instance_variable_set(:@run_journal, journal)

    lifecycle = []
    mission = Object.new
    mission.define_singleton_method(:defer!) { |reason:| lifecycle << [:mission_deferred, reason] }
    mission.define_singleton_method(:requeue_if_requested!) { false }
    recovery_error = Master::Result.err("delivery recovery failed", category: :delivery_failed)
    reachability = loop.instance_variable_get(:@reachability)

    Master::Fix::RunBudget.stub(:begin_run, ->(**) { lifecycle << [:budget_started] }) do
      Master::Fix::RunBudget.stub(:finish_run, ->(reason: "completed") { lifecycle << [:budget_finished, reason] }) do
        reachability.stub(:verify!, true) do
          loop.stub(:resume_active_transaction, recovery_error) do
            result = loop.send(
              :run_journaled,
              { "id" => "run-recovery", "remaining_seconds" => 60.0, "resumed" => false },
              files: [], target: @root, max_passes: 1, budget_seconds: 60,
              mission:, requested: false, incremental: false,
            )

            assert result.err?
            assert_equal :delivery_failed, result.category
          end
        end
      end
    end

    assert_equal 1, terminal_rows.size
    assert_equal "run-recovery", terminal_rows.first[:run_id]
    assert_equal :delivery_failed, terminal_rows.first[:state]
    assert_match(/delivery recovery failed/, terminal_rows.first[:message])
    deferred = lifecycle.find { |entry| entry.first == :mission_deferred }
    refute_nil deferred, "a failed recovery attempt must leave the durable mission retryable"
    assert_match(/attempt delivery_failed:/, deferred.last)
    assert lifecycle.any? { |entry| entry.first == :budget_finished },
           "recovery failure must stop the run budget watchdog"

    event = @bus.events.find { |row| row[:event] == "fix_loop:terminal" }
    refute_nil event, "recovery failure needs the canonical terminal event"
    assert_equal :delivery_failed, event[:payload][:state]
  end

  def test_pending_delivery_recovery_keeps_delivery_failure_typed
    loop = build_loop([])
    transport_error = Master::Result.err("push refused", category: :infrastructure)

    result = loop.stub(:retry_delivery, transport_error) do
      loop.send(
        :recover_pending_delivery,
        active_pass: { "transaction_id" => "tx-1", "pass" => 1 },
        run_id: "run-delivery", commit: "deadbeef",
      )
    end

    assert result.err?
    assert_equal :delivery_failed, result.category
    assert_match(/delivery recovery failed: push refused/, result.message)
    assert_equal :delivery_failed, loop.send(:terminal_state_for, result)
  end

  def test_terminal_state_preserves_every_typed_outcome
    loop = build_loop([])

    expected = {
      human_decision: :human_decision,
      plateau: :plateau,
      inconclusive: :inconclusive,
      reloading: :reloading,
      failed: :failed,
      delivery_failed: :delivery_failed,
      policy: :blocked,
      validation: :validation_failed,
    }

    expected.each do |category, state|
      result = Master::Result.err("terminal #{category}", category:)
      assert_equal state, loop.send(:terminal_state_for, result), category.to_s
    end
  end

  def test_a_canonical_repo_leaves_a_hashed_outcome_receipt_the_terminal_event_names
    %w[MASTER RAILS OPENBSD STUDIO].each { |tree| FileUtils.mkdir_p(File.join(@root, tree)) }
    loop = build_loop([])
    journal = Object.new
    journal.define_singleton_method(:history) { |**| [] }
    journal.define_singleton_method(:crash) { |*| nil }
    journal.define_singleton_method(:terminal) { |*| nil }
    loop.instance_variable_set(:@run_journal, journal)

    loop.send(:finish_run, Master::Result.ok("DONE: clean"), File.join(@root, "MASTER"), "run-9", requested: true)
    payload = @bus.events.find { |row| row[:event] == "fix_loop:terminal" }[:payload]
    receipt = payload[:outcome_receipt]

    assert_equal "MASTER", payload[:target]
    assert_equal "run-9", payload[:run_id]
    body = File.binread(File.join(@root, receipt[:source]))
    assert_equal Digest::SHA256.hexdigest(body), receipt[:sha256]
    assert_equal "run-9", JSON.parse(body).dig("details", "run_id")
  end

  def test_a_partial_workspace_leaves_no_outcome_receipt
    loop = build_loop([])
    journal = Object.new
    journal.define_singleton_method(:history) { |**| [] }
    journal.define_singleton_method(:crash) { |*| nil }
    journal.define_singleton_method(:terminal) { |*| nil }
    loop.instance_variable_set(:@run_journal, journal)

    loop.send(:finish_run, Master::Result.ok("DONE: clean"), @root, "run-10", requested: true)

    assert_nil @bus.events.find { |row| row[:event] == "fix_loop:terminal" }[:payload][:outcome_receipt]
  end

  def test_low_learned_fix_success_probability_forces_full_scope_on_incremental_runs
    loop = build_loop([])
    seen = []
    cognition = Object.new
    cognition.define_singleton_method(:predict_outcome) do |context:, action:|
      seen << [context, action]
      { status: :learned, samples: 6, success_probability: 0.3 }
    end
    loop.wire_cognition(cognition)

    guidance = loop.send(:outcome_guidance, target: "MASTER", incremental: true)

    assert_equal [["target=MASTER", "/fix"]], seen
    assert_equal false, guidance[:incremental]
    assert_equal :learned, guidance[:prediction][:status]
  end

  def test_sparse_fix_outcome_history_does_not_change_requested_scope
    loop = build_loop([])
    cognition = Object.new
    cognition.define_singleton_method(:predict_outcome) do |context:, action:|
      { status: :insufficient_data, samples: 2, success_probability: 0.25 }
    end
    loop.wire_cognition(cognition)

    guidance = loop.send(:outcome_guidance, target: "MASTER", incremental: true)

    assert_equal true, guidance[:incremental]
  end

  def test_finish_run_does_not_label_human_escalation_as_a_failed_repair
    loop = build_loop([])
    journal = Object.new
    journal.define_singleton_method(:history) { |**| [] }
    journal.define_singleton_method(:crash) { |*| nil }
    journal.define_singleton_method(:terminal) { |*| nil }
    loop.instance_variable_set(:@run_journal, journal)

    loop.send(:finish_run, Master::Result.ok("HUMAN_DECISION: approval required"), @root, "run-human", requested: true)
    event = @bus.events.find { |row| row[:event] == "fix_loop:terminal" }

    refute_nil event
    assert_equal :human_decision, event[:payload][:state]
    refute event[:payload].key?(:ok), "human escalation is not evidence that repair capability failed"
  end

  def test_finish_run_only_closes_the_journal
    calls = []
    journal = Object.new
    journal.define_singleton_method(:history) { |**| [] }
    journal.define_singleton_method(:crash) { |*| nil }
    journal.define_singleton_method(:terminal) { |*args, **kwargs| calls << [:terminal, args, kwargs] }

    loop = build_loop([])
    loop.instance_variable_set(:@run_journal, journal)

    loop.send(:finish_run, Master::Result.ok("DONE: clean"), @root, "r1", requested: true)

    assert_equal 1, calls.size
    assert_equal :terminal, calls.first.first
  end

  # 6. A clean tree the ground truth agrees with is the one state that says DONE.
  def test_a_clean_pass_asks_council_for_improvements
    asked = []
    council = Object.new
    council.define_singleton_method(:improve) do |files:, pass:, deadline:|
      asked << { files:, pass: }
      []
    end
    # Three passes: DONE takes two clean readings, so a clean first pass needs a second.
    result = prove(build_loop([], council:)).run(@root, max_passes: 3)

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

  def test_council_line_colon_requires_the_anchored_path
    file = File.join(@root, "dummy.yml")
    round = Master::Fix::FixLoop::CouncilRound.new(agent: nil, root: @root, bus: @bus)

    anchored = round.send(
      :improvement_findings,
      { cherry_picks: ["dummy.yml:12 simplify the declaration"] },
      [file],
    )
    ambiguous_line = round.send(
      :improvement_findings,
      { cherry_picks: ["Rails 8.2: simplify the declaration"] },
      [file],
    )

    assert_equal 12, anchored.first[:line]
    assert_empty ambiguous_line
  end

  def test_council_repo_root_still_produces_repo_relative_anchors
    file = File.join(@root, "MASTER", "dummy.yml")
    FileUtils.mkdir_p(File.dirname(file))
    File.write(file, "one
" + "two
" + "three
" + "four
" + "five
" + "six
" + "seven
")

    round = Master::Fix::FixLoop::CouncilRound.new(agent: nil, root: @root, bus: @bus)
    anchored = round.send(
      :improvement_findings,
      { cherry_picks: ["MASTER/dummy.yml:7 simplify this declaration"] },
      [file],
    )

    assert_equal file, anchored.first[:file]
    assert_equal 7, anchored.first[:line]
  end

  def test_council_allows_narrow_safe_remove_wording
    file = File.join(@root, "dummy.yml")
    round = Master::Fix::FixLoop::CouncilRound.new(agent: nil, root: @root, bus: @bus)

    safe = round.send(
      :improvement_findings,
      { cherry_picks: ["dummy.yml line 1 remove the unused parameter"] },
      [file],
    )
    unsafe = round.send(
      :improvement_findings,
      { cherry_picks: ["dummy.yml line 1 remove the behavior"] },
      [file],
    )

    assert_equal 1, safe.size
    assert_empty unsafe
  end

  def test_clean_tree_ideation_demands_anchored_candidates
    critique = Master::Review::Council::Critique.new(mode: :general, agent: nil)
    prompt = critique.send(:ideation_prompt, [])

    assert_includes prompt, "5 to 20 materially different candidates"
    assert_includes prompt, "repository-relative file and stable line or symbol"
    assert_includes prompt, "Do not invent defects"
  end

  def test_pending_wishlist_becomes_part_of_the_next_fix_mission
    FileUtils.mkdir_p(File.join(@root, "lib"))
    File.write(File.join(@root, "lib", "sample.rb"), "module Sample\nend\n")
    # Proposals are claimed against a git HEAD, so the fixture is a repository.
    system("git", "-C", @root, "init", "-q", "-b", "main")
    system("git", "-C", @root, "add", ".")
    system("git", "-C", @root, "-c", "user.name=t", "-c", "user.email=t@example.invalid", "commit", "-q", "-m", "fixture")
    wishlist = Master::Fix::Wishlist.new(root: @root, agent: RecordingAgent.new(<<~YAML))
      - id: boot_boundary
        title: Measure the boot boundary
        rationale: measure the startup seam
        anchor: lib/sample.rb:1
        change: record one deterministic startup receipt
        effort: cheap
        reversibility: reversible
        implementation: next_fix
        evidence: sample.rb exists
        proof:
          - ruby syntax
    YAML
    wishlist.call(state: "done", target: @root, run_id: "r1")

    plan = build_loop([]).send(:mission_plan, target: @root)

    assert_includes plan, "Pending automatic convergence proposals from the durable /fix ledger."
    assert_includes plan, "Measure the boot boundary"
    refute_includes plan, "### 1."
  end

  def test_structural_sweeps_normalise_each_tree_root_to_the_repository
    fix_loop = Master::Fix::FixLoop.allocate
    rails_root = File.join(Master::REPO_ROOT, "RAILS")

    sweeps = fix_loop.send(:build_sweeps, agent: nil, root: rails_root, bus: nil)

    restructure = sweeps.find { |sweep| sweep.is_a?(Master::Fix::RestructureSweep) }
    rename = sweeps.find { |sweep| sweep.is_a?(Master::Fix::RenameSweep) }

    assert_equal Master::REPO_ROOT, restructure.instance_variable_get(:@root)
    assert_equal Master::REPO_ROOT, rename.instance_variable_get(:@repo_root)
  end

  def test_a_converged_run_is_done
    result = prove(build_loop([])).run(@root)

    assert result.ok?
    assert_match(/\ADONE: /, result.value!)
  end

  def test_wishlist_open_proof_downgrades_done_to_plateau
    proposal = { "uid" => "wish-open", "status" => "claimed" }
    wishlist = Object.new
    wishlist.define_singleton_method(:call) { |**| "wishlist: drafted 1" }
    wishlist.define_singleton_method(:claimable) { |**| [proposal] }
    wishlist.define_singleton_method(:claim) { |rows, **| rows }
    wishlist.define_singleton_method(:pending_count) { |**| 0 }
    wishlist.define_singleton_method(:mark_verified) do |**|
      [{ "uid" => "wish-open", "status" => "applied", "proof_state" => "open" }]
    end

    loop = build_loop([])
    loop.instance_variable_set(:@wishlist, wishlist)
    loop.define_singleton_method(:wishlist_rounds) { 3 }
    journal = loop.instance_variable_get(:@run_journal)
    journal.define_singleton_method(:remaining_seconds) { |_run_id| 600 }
    journal.define_singleton_method(:history) { |limit:| [{ "id" => "r1", "next_pass" => 1 }] }
    journal.define_singleton_method(:next_pass) { |_record| 1 }
    loop.instance_variable_set(:@file_collector, Object.new.tap do |collector|
      collector.define_singleton_method(:collect) { |_target| [] }
    end)
    loop.define_singleton_method(:run_passes) { |**| Master::Result.ok("DONE: clean") }

    result = loop.send(
      :continue_with_wishlist,
      Master::Result.ok("DONE: clean"),
      files: [],
      target: @root,
      max_passes: 3,
      budget_seconds: 600,
      run_id: "r1",
    )

    assert_match(/\APLATEAU: /, result.value!)
    assert_includes result.value!, "wishlist proof inconclusive"
  end

  # 7. Running out of passes is not finishing.
  # Structure is a post-delivery checkpoint: the first ordinary pass delivers its
  # verified repair, then the bounded sweep runs on freshly observed files.
  def test_structure_checkpoint_runs_after_the_first_repair_pass
    target = File.join(@root, "RAILS")
    FileUtils.mkdir_p(target)

    order = []
    loop = Master::Fix::FixLoop.allocate
    loop.instance_variable_set(:@root, @root)
    discipline = Object.new
    discipline.define_singleton_method(:improving?) { false }
    loop.instance_variable_set(:@convergence_discipline, discipline)
    loop.define_singleton_method(:sweep_tree) do |target, run_id, phase:|
      order << [:structure, target, run_id, phase]
      []
    end
    loop.define_singleton_method(:run_one_pass) do |index, **|
      order << [:pass, index]
      nil
    end
    deadline = Object.new
    deadline.define_singleton_method(:expired?) { false }

    saved = ENV["MASTER_FIX_STRUCTURAL"]
    ENV["MASTER_FIX_STRUCTURAL"] = "1"
    result = loop.send(
      :run_passes,
      files: [],
      target:,
      max_passes: 1,
      deadline:,
      budget_seconds: 60,
      start_pass: 1,
      run_id: "r1",
    )

    assert_match(/\APLATEAU: /, result.value!)
    assert_equal [:pass, 0], order.first
    assert_equal [:structure, target, "r1-structure-checkpoint", :structure_first], order.last
  ensure
    saved.nil? ? ENV.delete("MASTER_FIX_STRUCTURAL") : ENV["MASTER_FIX_STRUCTURAL"] = saved
  end

  def test_structural_sweep_failure_is_not_swallowed
    sweep = Object.new
    def sweep.run(**) = raise "boom"

    loop = build_loop([])
    loop.instance_variable_set(:@sweeps, [sweep])

    error = assert_raises(RuntimeError) do
      loop.send(:sweep_tree, @root, "r1")
    end

    assert_match(/structural sweep failed/, error.message)
    assert_match(/boom/, error.message)
  end

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

  # Every issue receives several materially distinct options, and headings
  # or near-duplicate paraphrases never take slots away from another issue.
  def test_cherry_pick_keeps_three_distinct_candidates_per_issue
    feedback = [
      { feedback: "the flag name hides what it checks" },
      { feedback: "the retry has no ceiling" }
    ]
    ideas = [
      "Solutions:",
      "issue 1 rename the flag to describe the feature it checks",
      "issue 1 move the flag decision into the existing settings owner",
      "issue 1 remove the duplicate branch and reuse canonical configuration",
      "issue 1 rename the flag to describe the feature it checks again",
      "issue 1 use a shorter name for the flag",
      "issue 2 cap retry attempts and use bounded backoff",
      "issue 2 stop retrying immediately when the error is permanent",
      "issue 2 read the retry cap from the existing policy with a safe default",
      "issue 2 cap retry attempts and use bounded backoff again"
    ].join("\n")

    picks = Master::Review::Council::Critique::CherryPick.rank(feedback, ideas)

    assert_operator picks.size, :<=, Master::Review::Council::Critique::CherryPick::LIMIT
    assert_equal 3, picks.count { |pick| pick.match?(/\bissue 1\b/i) }
    assert_equal 3, picks.count { |pick| pick.match?(/\bissue 2\b/i) }
    refute_includes picks, "Solutions:"
  end

  def test_clean_tree_improvement_uses_one_winner_per_issue_or_anchor
    cherry = Master::Review::Council::Critique::CherryPick
    picks = [
      "issue 1 rename the flag to clarify behavior",
      "issue 1 move flag ownership to settings",
      "issue 2 cap retries with backoff",
      "MASTER/lib/flags.rb line 12 simplify the parser",
      "MASTER/lib/flags.rb line 12 reuse the existing parser",
      "RAILS/brgen/app/models/post.rb line 40 remove repeated coercion"
    ]

    winners = cherry.one_per_issue(picks)

    assert_equal 4, winners.size
    assert_equal picks.values_at(0, 2, 3, 5), winners
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
    lines = pass.preview_lines(total: 107, laws: counts, files: { "lib/voice/engines.rb" => 20 })

    assert_equal "preview: 107 findings at warning or above to repair", lines.lines.first.chomp
    assert_match(/^preview laws: FEW_ARGUMENTS 28, /, lines)
    assert_match(/, and 1 more$/, lines.lines[1].chomp)
    assert_equal "preview files: engines.rb 20", lines.lines[2].chomp
    refute_match(/lib.voice.engines/, lines)
  end

  def test_one_finding_is_not_findings
    pass = Master::CLI::Pipeline::Pass.allocate
    assert_equal "preview: 1 finding at warning or above to repair",
                 pass.preview_lines(total: 1, laws: {}, files: {}).lines.first.chomp
  end

  def test_check_chain_is_explicitly_top_level_from_master_namespace
    assert defined?(::Operator::CheckChain)
    refute defined?(Master::Operator::CheckChain)
  end

  def test_structural_context_uses_real_file_predicates
    source = File.read(File.join(Master::ROOT, "lib", "fix", "restructure_sweep", "context.rb"))
    refute_includes source, "select(&:file?)"
    refute_includes source, "select(&:directory?)"
    assert_includes source, "File.file?(path)"
    assert_includes source, "File.directory?(path)"
  end

  def test_explicit_governed_trees_are_queued_in_operator_order
    root = "/tmp/pub4"
    targets = Master::CLI::CommandRegistry.send(
      :fix_targets, "MASTER RAILS OPENBSD STUDIO", root:
    )

    assert_equal %w[MASTER RAILS OPENBSD STUDIO].map { |tree| File.join(root, tree) }, targets
  end

  def test_single_target_and_mixed_arguments_are_not_reinterpreted
    root = "/tmp/pub4"
    assert_equal ["MASTER"], Master::CLI::CommandRegistry.send(:fix_targets, "MASTER", root:)
    assert_equal ["MASTER RAILS --apply"], Master::CLI::CommandRegistry.send(:fix_targets, "MASTER RAILS --apply", root:)
  end
end
