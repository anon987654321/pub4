# frozen_string_literal: true

require_relative "test_helper"
require "tmpdir"
require "fileutils"
require "open3"

# The multi-file restructure /fix runs after its repair passes. Every case runs
# in a throwaway repository with its own bare remote, never this checkout.
class TestRestructure < Minitest::Test
  Restructure = Master::Fix::Restructure

  class Proof
    def initialize(failure = nil) = @failure = failure
    def baseline(_plan) = {}
    def failure(_plan, _before) = @failure
  end

  def setup
    @tmp = Dir.mktmpdir("restructure_test")
    remote = File.join(@tmp, "remote.git")
    @repo = File.join(@tmp, "work")
    sh("git", "init", "--bare", "--initial-branch=main", remote, chdir: @tmp)
    sh("git", "clone", remote, @repo, chdir: @tmp)
    %w[user.email=t@example.invalid user.name=T commit.gpgsign=false].each do |pair|
      sh("git", "config", *pair.split("=", 2), chdir: @repo)
    end
    write("MASTER/lib/big.rb", "class Big\n  def a = 1\n  def b = 2\nend\n")
    write("MASTER/lib/tiny.rb", "TINY = 1\n")
    # The sacred-path policy fails closed without a soul.yml.
    write("MASTER/data/soul.yml", "absolute:\n  sacred_paths:\n    - data/soul.yml\n")
    # RailsProof proves the apps RAILS/apps.yml registers.
    write("RAILS/apps.yml", "apps:\n  brgen: {}\n  amber: {}\n  bsdports: {}\n")
    sh("git", "add", "-A", chdir: @repo)
    sh("git", "commit", "-m", "first", chdir: @repo)
    sh("git", "push", "-u", "origin", "main", chdir: @repo)
    File.open(File.join(@repo, ".git", "info", "exclude"), "a") { |file| file.puts("/.master/") }
  end

  def teardown = FileUtils.remove_entry(@tmp)

  def sh(*args, chdir:)
    out, status = Open3.capture2e(*args, chdir:)
    raise "#{args.join(" ")}: #{out}" unless status.success?

    out
  end

  def write(path, text)
    FileUtils.mkdir_p(File.dirname(File.join(@repo, path)))
    File.write(File.join(@repo, path), text)
  end

  def read(path) = File.read(File.join(@repo, path))

  def split_plan
    Restructure::Plan.parse(<<~TEXT)
      SUMMARY: split Big and absorb tiny.rb
      OPERATIONS: split
      === WRITE MASTER/lib/big.rb
      class Big
        def a = 1
      end
      === WRITE MASTER/lib/big/second.rb
      class Big
        def b = 2
      end
      === DELETE MASTER/lib/tiny.rb
      === END
    TEXT
  end

  def restructure(proof = Proof.new) = Restructure.new(repo_root: @repo, proof:)

  def test_a_plan_reads_its_explicit_operations
    plan = split_plan

    assert_equal ["split"], plan.operations
  end

  def test_a_plan_rejects_missing_operations
    plan = Restructure::Plan.parse(<<~TEXT)
      SUMMARY: missing operation
      === WRITE MASTER/lib/big.rb
      class Big; end
      === END
    TEXT

    reason = plan.validate_operations!(transformation_plan: Master::Fix::TransformationPlan.new(root: Master::ROOT))
    assert_equal "restructure plan names no operations", reason
  end

  def test_a_plan_rejects_out_of_order_operations
    plan = Restructure::Plan.parse("OPERATIONS: rename, merge\n=== DELETE MASTER/lib/tiny.rb\n=== END\n")
    reason = plan.validate_operations!(transformation_plan: Master::Fix::TransformationPlan.new(root: Master::ROOT))

    assert_includes reason, "out of constitutional order"
  end

  def test_a_plan_rejects_an_operation_outside_the_problem_candidates
    plan = Restructure::Plan.parse("OPERATIONS: split\n=== DELETE MASTER/lib/tiny.rb\n=== END\n")
    reason = plan.validate_operations!(
      transformation_plan: Master::Fix::TransformationPlan.new(root: Master::ROOT),
      allowed_operations: ["remove"],
    )

    assert_includes reason, "outside the problem's candidate set"
  end

  def test_plan_rejects_two_ordered_operations_in_one_atomic_restructure
    plan = Restructure::Plan.parse("OPERATIONS: remove, simplify\n=== DELETE MASTER/lib/tiny.rb\n=== END\n")
    reason = plan.validate_operations!(transformation_plan: Master::Fix::TransformationPlan.new(root: Master::ROOT))

    assert_includes reason, "one transformation per restructure"
  end

  def test_plan_rejects_multiple_named_deletions
    plan = Restructure::Plan.parse("OPERATIONS: remove\n=== DELETE MASTER/lib/a.rb\n=== DELETE MASTER/lib/b.rb\n=== END\n")
    reason = plan.validate_operations!(transformation_plan: Master::Fix::TransformationPlan.new(root: Master::ROOT))

    assert_includes reason, "BATCH_DELETE"
  end

  def test_plan_rejects_mixed_test_and_production_changes
    plan = Restructure::Plan.parse(<<~TEXT)
      SUMMARY: mix source and tests
      OPERATIONS: split
      === WRITE MASTER/lib/big.rb
      class Big; end
      === WRITE MASTER/test/test_big.rb
      class TestBig; end
      === END
    TEXT
    reason = plan.validate_operations!(transformation_plan: Master::Fix::TransformationPlan.new(root: Master::ROOT))

    assert_includes reason, "MIXED_COMMIT"
  end

  def test_plan_spares_a_production_only_change
    plan = Restructure::Plan.parse("OPERATIONS: simplify\n=== WRITE MASTER/lib/big.rb\nclass Big; end\n=== END\n")

    assert_nil plan.validate_operations!(transformation_plan: Master::Fix::TransformationPlan.new(root: Master::ROOT))
  end

  def test_a_plan_reads_its_writes_deletes_and_summary
    plan = split_plan

    assert_equal "split Big and absorb tiny.rb", plan.summary
    assert_equal %w[MASTER/lib/big.rb MASTER/lib/big/second.rb], plan.writes.keys
    assert_equal ["MASTER/lib/tiny.rb"], plan.deletes
    assert_equal "class Big\n  def a = 1\nend\n", plan.writes["MASTER/lib/big.rb"]
  end

  def test_mutation_boundary_rejects_out_of_order_operations_before_writing
    original = read("MASTER/lib/tiny.rb")
    plan = Restructure::Plan.parse("OPERATIONS: rename, merge\n=== DELETE MASTER/lib/tiny.rb\n=== END\n")
    reviewed = false

    result = restructure.call(
      plan,
      message: "x",
      review: ->(_diff) { reviewed = true },
    )

    refute result.ok?
    assert_includes result.message, "out of constitutional order"
    refute reviewed
    assert_equal original, read("MASTER/lib/tiny.rb")
  end

  def test_stale_reads_block_a_restructure_before_any_file_is_changed
    truth = Object.new
    truth.define_singleton_method(:fresh?) { |_path| false }
    result = Restructure.new(repo_root: @repo, ground_truth: truth).call(
      split_plan, message: "refactor: split Big", review: ->(_diff) {}
    )

    refute result.ok?
    assert_match(/ground_truth: stale read required/, result.message)
    assert_equal "TINY = 1\n", read("MASTER/lib/tiny.rb")
    assert_equal "class Big\n  def a = 1\n  def b = 2\nend\n", read("MASTER/lib/big.rb")
    refute File.exist?(File.join(@repo, "MASTER/lib/big/second.rb"))
    assert_empty sh("git", "status", "--porcelain", chdir: @repo).strip
  end

  def test_a_failed_delivery_safety_check_rolls_back_the_whole_plan
    Operator::RatchetSponsor.stub(:validate!, ->(**_kwargs) { raise "ratchet sponsorship required" }) do
      result = restructure.call(split_plan, message: "refactor: split Big", review: ->(_diff) {})
      refute result.ok?
      assert_match(/delivery safety: RuntimeError: ratchet sponsorship required/, result.message)
    end

    assert_equal "TINY = 1\n", read("MASTER/lib/tiny.rb")
    refute File.exist?(File.join(@repo, "MASTER/lib/big/second.rb"))
    assert_empty sh("git", "status", "--porcelain", chdir: @repo).strip
  end

  def test_an_approved_restructure_is_committed_and_pushed
    result = Operator::RatchetSponsor.stub(:validate!, true) do
      restructure.call(split_plan, message: "refactor: split Big", review: ->(_diff) {})
    end

    assert result.ok?, -> { result.message }
    refute File.exist?(File.join(@repo, "MASTER/lib/tiny.rb"))
    assert_equal "class Big\n  def b = 2\nend\n", read("MASTER/lib/big/second.rb")
    assert_equal "refactor: split Big", sh("git", "log", "-1", "--format=%s", "origin/main", chdir: @repo).strip
    assert_empty sh("git", "status", "--porcelain", chdir: @repo)
  end

  def test_an_approved_restructure_returns_before_and_after_hash_evidence
    result = Operator::RatchetSponsor.stub(:validate!, true) do
      restructure.call(split_plan, message: "refactor: split Big", review: ->(_diff) {})
    end

    assert result.ok?, -> { result.message }
    evidence = result.value!.fetch(:evidence)
    assert_equal ["MASTER/lib/big.rb", "MASTER/lib/big/second.rb", "MASTER/lib/tiny.rb"].sort, evidence.fetch(:before).keys.sort
    assert_equal evidence.fetch(:before).keys.sort, evidence.fetch(:after).keys.sort
    refute_equal evidence.fetch(:before).fetch("MASTER/lib/big.rb"), evidence.fetch(:after).fetch("MASTER/lib/big.rb")
    assert_equal ["MASTER/lib/big/second.rb"], evidence.fetch(:written).reject { |path| path == "MASTER/lib/big.rb" }
    assert_equal ["MASTER/lib/tiny.rb"], evidence.fetch(:deleted)
    assert_equal ["split"], evidence.fetch(:operations)
    assert_equal "review_and_tree_proof_held", evidence.fetch(:proof)
  end

  def test_a_rejected_restructure_puts_every_file_back
    seen = nil
    reject = lambda do |diff|
      seen = diff
      "REJECT: moves nothing useful"
    end
    result = restructure.call(split_plan, message: "x", review: reject)

    refute result.ok?
    assert_includes seen, "+++ MASTER/lib/big/second.rb"
    assert_includes seen, "+++ /dev/null"
    assert_equal "TINY = 1\n", read("MASTER/lib/tiny.rb")
    assert_equal "class Big\n  def a = 1\n  def b = 2\nend\n", read("MASTER/lib/big.rb")
    refute File.exist?(File.join(@repo, "MASTER/lib/big/second.rb"))
  end

  def test_a_failed_proof_puts_every_file_back
    result = restructure(Proof.new("MASTER no longer eager-loads")).call(split_plan, message: "x", review: ->(_d) {})

    assert_includes result.message, "eager-loads"
    assert_equal "TINY = 1\n", read("MASTER/lib/tiny.rb")
  end

  def test_deletion_proof_refuses_a_live_production_reference
    write("MASTER/lib/consumer.rb", "require_relative \"producer\"\n")
    write("MASTER/lib/producer.rb", "class Producer; end\n")
    sh("git", "add", "-A", chdir: @repo)
    sh("git", "commit", "-m", "consumer", chdir: @repo)

    plan = Restructure::Plan.parse(<<~TEXT)
      SUMMARY: remove producer
      OPERATIONS: remove
      === DELETE MASTER/lib/producer.rb
      === END
    TEXT
    proof = Restructure::Proof.for("MASTER", @repo)
    baseline = proof.baseline(plan)

    File.delete(File.join(@repo, "MASTER/lib/producer.rb"))

    assert_match(/production references/, proof.failure(plan, baseline))
  end

  def test_master_restructure_ratchets_recursive_core_ceiling
    write("MASTER/data/spine.yml", "spine:\n  core_recursive_files: 2\n")
    write("MASTER/lib/core/one.rb", "module One; end\n")
    write("MASTER/lib/core/two.rb", "module Two; end\n")
    sh("git", "add", "-A", chdir: @repo)
    sh("git", "commit", "-m", "core baseline", chdir: @repo)

    plan = Restructure::Plan.parse(<<~TEXT)
      SUMMARY: remove dead core file
      OPERATIONS: remove
      === DELETE MASTER/lib/core/two.rb
      === END
    TEXT
    ratcheted = restructure.send(:ratcheted_plan, plan)

    assert_equal "spine:\n  core_recursive_files: 1\n", ratcheted.writes.fetch("MASTER/data/spine.yml")
  end

  # One stem across controller, service and policy is the parallel hierarchy the scan names.
  def write_user_hierarchy
    %w[Controller Service Policy].each do |role|
      write("MASTER/lib/user_#{role.downcase}.rb", "class User#{role}; def run; 1; end; end\n")
    end
  end

  def test_cross_file_architecture_is_restructure_evidence
    write_user_hierarchy
    sh("git", "add", "-A", chdir: @repo)
    sh("git", "commit", "-m", "parallel architecture", chdir: @repo)

    findings = Master::Fix::RestructureSweep::Context.structural_findings(File.join(@repo, "MASTER"))
    finding = findings.find { |_path, rule, _message, _related| rule == "PARALLEL_HIERARCHY" }

    refute_nil finding
    assert_equal 3, finding.fetch(3).size
    assert_includes finding.fetch(3), File.join(@repo, "MASTER/lib/user_controller.rb")
  end

  def test_dead_production_subtree_becomes_an_autonomous_candidate
    write("MASTER/lib/dead_machine/base.rb", "class DeadMachine; end\n")
    write("MASTER/lib/dead_machine/state.rb", "class DeadMachineState < DeadMachine; end\n")
    write("MASTER/lib/dead_machine/runner.rb", "require_relative \"state\"\nclass DeadMachineRunner; end\n")
    sh("git", "add", "-A", chdir: @repo)
    sh("git", "commit", "-m", "dead subtree", chdir: @repo)

    findings = Master::Fix::RestructureSweep::Context.structural_findings(File.join(@repo, "MASTER"))
    finding = findings.find { |_path, rule, _message, _related| rule == "DEAD_SUBTREE" }

    refute_nil finding
    assert_includes finding.fetch(2), "no production references"
    assert_equal 3, finding.fetch(3).size
  end

  def test_context_shows_related_architecture_files
    write_user_hierarchy
    context = Master::Fix::RestructureSweep::Context.new(
      @repo,
      File.join(@repo, "MASTER/lib/user_controller.rb"),
      related: [
        File.join(@repo, "MASTER/lib/user_service.rb"),
        File.join(@repo, "MASTER/lib/user_policy.rb"),
      ],
    )

    text = context.to_s
    assert_includes text, "Related file, MASTER/lib/user_service.rb:"
    assert_includes text, "Related file, MASTER/lib/user_policy.rb:"
  end

  def test_restructure_exit_reports_done_after_a_fresh_empty_scan
    events = []
    bus = Object.new
    bus.define_singleton_method(:publish) { |name, **fields| events << [name, fields] }
    sweep = Master::Fix::RestructureSweep.new(agent: nil, repo_root: @repo, bus:)
    sweep.define_singleton_method(:candidates) { |_target, _run_id| [] }

    result = sweep.run_tree(File.join(@repo, "MASTER"), "empty-scan", attempts: 1, rounds: 1, keeps: 1)

    assert_empty result
    exit_event = events.find { |name, _fields| name == "fix_loop:restructure_exit" }
    assert_equal "DONE", exit_event.last.fetch(:state)
  end

  def test_restructure_exit_reports_a_partial_attempt_budget_as_limit_reached
    problem_class = Struct.new(:id, :size, :laws, :files, :candidate_operations, :findings, :reason, :confidence, keyword_init: true)
    path = File.join(@repo, "MASTER/lib/big.rb")
    problems = 2.times.map do |index|
      problem_class.new(
        id: "p#{index}", size: 1, laws: ["GOD_CLASS"], files: [path],
        candidate_operations: %w[split], findings: [[path, "GOD_CLASS", "line 1: job", []]],
        reason: "one finding", confidence: :single,
      )
    end
    events = []
    bus = Object.new
    bus.define_singleton_method(:publish) { |name, **fields| events << [name, fields] }
    sweep = Master::Fix::RestructureSweep.new(agent: nil, repo_root: @repo, bus:)
    sweep.define_singleton_method(:candidates) { |_target, _run_id| problems }
    sweep.define_singleton_method(:attempt) { |_problem, candidate_map:| nil }

    sweep.run_tree(File.join(@repo, "MASTER"), "budget-test", attempts: 1, rounds: 1, keeps: 1)

    exit_event = events.find { |name, _fields| name == "fix_loop:restructure_exit" }
    assert_equal "LIMIT_REACHED", exit_event.last.fetch(:state)
  end

  def test_restructure_review_rejects_bare_approval
    problem_class = Struct.new(:id, :findings, :files, :laws, :reason, :confidence, :candidate_operations, keyword_init: true)
    path = File.join(@repo, "MASTER/lib/big.rb")
    problem = problem_class.new(
      id: "p-review", findings: [[path, "GOD_CLASS", "line 1: test finding", []]],
      files: [path], laws: %w[GOD_CLASS], reason: "one finding",
      confidence: :single, candidate_operations: %w[split],
    )
    agent = Object.new
    agent.define_singleton_method(:ask) { |_prompt, operation:| "APPROVE" }
    sweep = Master::Fix::RestructureSweep.new(agent:, repo_root: @repo)
    plan = Restructure::Plan.parse("SUMMARY: split Big\nOPERATIONS: split\n=== WRITE MASTER/lib/big.rb\nclass Big; end\n=== END\n")

    result = sweep.send(:verdict, problem, plan, "diff", scorecard_before: {})

    assert_match(/review: APPROVE/, result)
  end

  def test_restructure_review_accepts_approval_with_evidence
    problem_class = Struct.new(:id, :findings, :files, :laws, :reason, :confidence, :candidate_operations, keyword_init: true)
    path = File.join(@repo, "MASTER/lib/big.rb")
    problem = problem_class.new(
      id: "p-review", findings: [[path, "GOD_CLASS", "line 1: test finding", []]],
      files: [path], laws: %w[GOD_CLASS], reason: "one finding",
      confidence: :single, candidate_operations: %w[split],
    )
    agent = Object.new
    agent.define_singleton_method(:ask) do |_prompt, operation:|
      "APPROVE: relevant tests passed, the unchanged import paths are recorded, and the file/line scorecard has no unexplained regression"
    end
    sweep = Master::Fix::RestructureSweep.new(agent:, repo_root: @repo)
    plan = Restructure::Plan.parse("SUMMARY: split Big\nOPERATIONS: split\n=== WRITE MASTER/lib/big.rb\nclass Big; end\n=== END\n")

    assert_nil sweep.send(:verdict, problem, plan, "diff", scorecard_before: {})
  end

  def test_candidate_map_scores_actual_findings_without_padding
    big = File.join(@repo, "MASTER/lib/big.rb")
    problem = Struct.new(:id, :findings, :files, :laws, :reason, :confidence, :candidate_operations, keyword_init: true).new(
      id: "p1",
      findings: [[big, "GOD_CLASS", "line 2: two jobs", []]],
      files: [big],
      laws: %w[GOD_CLASS],
      reason: "one finding",
      confidence: :high,
      candidate_operations: %w[split],
    )
    sweep = Master::Fix::RestructureSweep.new(agent: nil, repo_root: @repo)
    ranked = sweep.send(:ranked_candidate_map, [problem])
    map = sweep.send(:render_candidate_map, ranked)
    prompt = sweep.send(:proposal, "MASTER", problem, candidate_map: map)

    assert_equal [1, 3], [ranked.first.fetch(:payoff), ranked.first.fetch(:risk)]
    assert_includes map, "Evidence-backed candidates: 1; distinct target paths: 1"
    assert_includes map, "shortfalls: 14 candidates and 2 paths"
    assert_includes prompt, "line 2: two jobs"
    assert_includes prompt, "No source has changed during this phase"
  end

  def test_proposal_carries_every_playbook_method_and_check
    big = File.join(@repo, "MASTER/lib/big.rb")
    problem = Struct.new(:id, :findings, :files, :laws, :reason, :confidence, :candidate_operations, keyword_init: true).new(
      id: "p1",
      findings: [[big, "GOD_CLASS", "two jobs", []]],
      files: [big],
      laws: %w[GOD_CLASS],
      reason: "one finding",
      confidence: :high,
      candidate_operations: %w[split],
    )
    sweep = Master::Fix::RestructureSweep.new(agent: nil, repo_root: @repo)
    map = sweep.send(:render_candidate_map, sweep.send(:ranked_candidate_map, [problem]))
    prompt = sweep.send(:proposal, "MASTER", problem, candidate_map: map)
    playbook = Master::Fix::TransformationPlan.new.refactoring_playbook

    playbook.fetch("methods").each { |entry| assert_includes prompt, "#{entry.fetch("id")}: #{entry.fetch("action")}" }
    playbook.fetch("checks").each { |check| assert_includes prompt, check }
    assert_includes prompt, "Below three sites keep the duplication"
    assert_includes prompt, "Measured baseline scorecard"
    assert_includes prompt, "Co-change evidence"
    assert_includes prompt, "Choose exactly one transformation"
    assert_includes prompt, "Evidence-backed candidates"
    assert_includes prompt, "No source has changed during this phase"
  end

  def test_each_tree_is_proved_its_own_way
    assert_equal %w[MASTER RAILS OPENBSD STUDIO], Master::Fix::RestructureSweep::Contracts::BY_TREE.keys
    assert_instance_of Restructure::MasterProof, Restructure::Proof.for("MASTER", @repo)
    assert_instance_of Restructure::RailsProof, Restructure::Proof.for("RAILS", @repo)
    assert_instance_of Restructure::ScriptProof, Restructure::Proof.for("OPENBSD", @repo)
    assert_instance_of Restructure::ScriptProof, Restructure::Proof.for("STUDIO", @repo)
    assert_includes Master::Fix::RestructureSweep::Contracts.for("STUDIO"), "canonical media and production source tree"
  end

  def test_rails_proof_includes_mounted_engine_tests
    # A brgen vertical is an engine beside brgen at RAILS/brgen_<name>, reached from brgen.
    FileUtils.mkdir_p(File.join(@repo, "RAILS/brgen/test"))
    FileUtils.mkdir_p(File.join(@repo, "RAILS/brgen_takeaway/test/models/takeaway"))
    engine_test = File.join(@repo, "RAILS/brgen_takeaway/test/models/takeaway/order_test.rb")
    File.write(engine_test, "class OrderTest < Minitest::Test; end\n")
    order = "RAILS/brgen_takeaway/app/models/takeaway/order.rb"
    plan = Restructure::Plan.parse("OPERATIONS: split\n=== WRITE #{order}\nmodule Takeaway\nend\n=== END\n")
    proof = Restructure::RailsProof.new(repo_root: @repo, tree: "RAILS")
    assert_includes proof.send(:test_files, plan).map { |file| File.expand_path(file) }, engine_test
  end

  def test_unaliased_move_is_refused
    write("MASTER/lib/movable.rb", "class Movable\nend\n")
    write("MASTER/lib/movable_new.rb", "class Movable\nend\n")
    sh("git", "add", "-A", chdir: @repo)
    sh("git", "commit", "-m", "movable baseline", chdir: @repo)

    plan = Restructure::Plan.parse(<<~TEXT)
      SUMMARY: move Movable
      OPERATIONS: relocate
      === WRITE MASTER/lib/movable_new.rb
      class Movable
      end
      === DELETE MASTER/lib/movable.rb
      === END
    TEXT
    proof = Restructure::ScriptProof.new(repo_root: @repo, tree: "MASTER")
    before = proof.baseline(plan)
    File.delete(File.join(@repo, "MASTER/lib/movable.rb"))

    assert_match(/UNALIASED_MOVE/, proof.failure(plan, before))
  end

  def test_dead_constant_deletion_is_not_a_move
    plan = Restructure::Plan.parse("OPERATIONS: remove\n=== DELETE MASTER/lib/tiny.rb\n=== END\n")
    proof = Restructure::ScriptProof.new(repo_root: @repo, tree: "MASTER")
    before = proof.baseline(plan)
    File.delete(File.join(@repo, "MASTER/lib/tiny.rb"))

    assert_nil proof.send(:unaliased_move_failure, plan, before)
  end

  def test_a_written_file_must_still_parse_as_what_it_is
    { "a.rb" => "def x\n", "a.yml" => "a: [1\n", "a.json" => "{", "a.sh" => "if true; then\n" }.each do |name, text|
      write(name, text)

      refute Restructure::Syntax.valid?(File.join(@repo, name)), name
    end
    write("ok.yml", "a: 1\n")

    assert Restructure::Syntax.valid?(File.join(@repo, "ok.yml"))
  end

  def test_rails_restructure_proof_refuses_a_deleted_view_with_a_logical_render_reference
    view = "RAILS/brgen/app/views/posts/_card.html.erb"
    caller = "RAILS/brgen/app/views/posts/index.html.erb"
    write(view, "<%# card %>\n")
    write(caller, '<%= render "posts/card" %>\n')
    plan = Restructure::Plan.parse("OPERATIONS: remove\n=== DELETE #{view}\n=== END\n")
    proof = Restructure::RailsProof.new(repo_root: @repo, tree: "RAILS")
    before = proof.baseline(plan)
    File.delete(File.join(@repo, view))

    assert_match(/render references/, proof.failure(plan, before))
  end

  def test_erb_restructure_content_is_syntax_checked
    write("RAILS/brgen/app/views/posts/card.html.erb", '<%= missing( %>\n')

    refute Restructure::Syntax.valid?(File.join(@repo, "RAILS/brgen/app/views/posts/card.html.erb"))
  end

  # The box's mirrored paths and the database's history mean something outside
  # the tree, so no restructure moves them.
  def test_paths_that_mirror_the_box_or_the_database_are_refused
    box = Restructure::Plan.parse("OPERATIONS: relocate\n=== WRITE OPENBSD/etc/relayd.conf\nx\n=== END\n")
    migration = Restructure::Plan.parse("OPERATIONS: remove\n=== DELETE RAILS/brgen/db/migrate/1_x.rb\n=== END\n")

    assert_includes Restructure.new(repo_root: @repo, tree: "OPENBSD", proof: Proof.new)
                               .call(box, message: "x", review: ->(_d) {}).message, "off limits"
    assert_includes Restructure.new(repo_root: @repo, tree: "RAILS", proof: Proof.new)
                               .call(migration, message: "x", review: ->(_d) {}).message, "off limits"
  end

  # What soul.yml declares sacred is refused; laws.yml carries no list of its own.
  def test_the_kernel_and_other_trees_are_refused
    write("MASTER/data/soul.yml", "absolute:\n  sacred_paths:\n    - data/\n    - lib/review/scan/\n")
    kernel = Restructure::Plan.parse("OPERATIONS: relocate\n=== WRITE MASTER/data/soul.yml\nx\n=== END\n")
    scanner = Restructure::Plan.parse("OPERATIONS: split\n=== WRITE MASTER/lib/review/scan/law.rb\nx\n=== END\n")

    assert_includes restructure.call(scanner, message: "x", review: ->(_d) {}).message, "immutable"
    outside = Restructure::Plan.parse("OPERATIONS: relocate\n=== WRITE RAILS/app.rb\nx\n=== END\n")

    assert_includes restructure.call(kernel, message: "x", review: ->(_d) {}).message, "immutable"
    assert_includes restructure.call(outside, message: "x", review: ->(_d) {}).message, "outside MASTER/"
  end
end
