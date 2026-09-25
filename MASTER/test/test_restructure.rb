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
    sh("git", "add", "-A", chdir: @repo)
    sh("git", "commit", "-m", "first", chdir: @repo)
    sh("git", "push", "-u", "origin", "main", chdir: @repo)
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

  def test_a_plan_reads_its_writes_deletes_and_summary
    plan = split_plan

    assert_equal "split Big and absorb tiny.rb", plan.summary
    assert_equal %w[MASTER/lib/big.rb MASTER/lib/big/second.rb], plan.writes.keys
    assert_equal ["MASTER/lib/tiny.rb"], plan.deletes
    assert_equal "class Big\n  def a = 1\nend\n", plan.writes["MASTER/lib/big.rb"]
  end

  def test_an_approved_restructure_is_committed_and_pushed
    result = restructure.call(split_plan, message: "refactor: split Big", review: ->(_diff) {})

    assert result.ok?, -> { result.message }
    refute File.exist?(File.join(@repo, "MASTER/lib/tiny.rb"))
    assert_equal "class Big\n  def b = 2\nend\n", read("MASTER/lib/big/second.rb")
    assert_equal "refactor: split Big", sh("git", "log", "-1", "--format=%s", "origin/main", chdir: @repo).strip
    assert_empty sh("git", "status", "--porcelain", chdir: @repo)
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
      === DELETE MASTER/lib/producer.rb
      === END
    TEXT
    proof = Restructure::Proof.new(repo_root: @repo, tree: "MASTER")
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
      === DELETE MASTER/lib/core/two.rb
      === END
    TEXT
    ratcheted = restructure.send(:ratcheted_plan, plan)

    assert_equal "  core_recursive_files: 1\n", ratcheted.writes.fetch("MASTER/data/spine.yml")
  end

  def test_cross_file_architecture_is_restructure_evidence
    write("MASTER/lib/alpha_service.rb", "class AlphaService; def run; 1; end; end\n")
    write("MASTER/lib/beta_service.rb", "class BetaService; def run; 1; end; end\n")
    write("MASTER/lib/gamma_service.rb", "class GammaService; def run; 1; end; end\n")
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
    context = Master::Fix::RestructureSweep::Context.new(
      @repo,
      File.join(@repo, "MASTER/lib/user_controller.rb"),
      related: [
        File.join(@repo, "MASTER/lib/user_service.rb"),
        File.join(@repo, "MASTER/lib/user_policy.rb"),
      ],
    )

    text = context.to_s
    assert_includes text, "Related architecture evidence:"
    assert_includes text, "MASTER/lib/user_service.rb"
    assert_includes text, "MASTER/lib/user_policy.rb"
  end

  def test_each_tree_is_proved_its_own_way
    assert_instance_of Restructure::MasterProof, Restructure::Proof.for("MASTER", @repo)
    assert_instance_of Restructure::RailsProof, Restructure::Proof.for("RAILS", @repo)
    assert_instance_of Restructure::ScriptProof, Restructure::Proof.for("OPENBSD", @repo)
    assert_instance_of Restructure::ScriptProof, Restructure::Proof.for("STUDIO", @repo)
  end

  def test_a_written_file_must_still_parse_as_what_it_is
    { "a.rb" => "def x\n", "a.yml" => "a: [1\n", "a.json" => "{", "a.sh" => "if true; then\n" }.each do |name, text|
      write(name, text)

      refute Restructure::Syntax.valid?(File.join(@repo, name)), name
    end
    write("ok.yml", "a: 1\n")

    assert Restructure::Syntax.valid?(File.join(@repo, "ok.yml"))
  end

  # The box's mirrored paths and the database's history mean something outside
  # the tree, so no restructure moves them.
  def test_paths_that_mirror_the_box_or_the_database_are_refused
    box = Restructure::Plan.parse("=== WRITE OPENBSD/etc/relayd.conf\nx\n=== END\n")
    migration = Restructure::Plan.parse("=== DELETE RAILS/brgen/db/migrate/1_x.rb\n=== END\n")

    assert_includes Restructure.new(repo_root: @repo, tree: "OPENBSD", proof: Proof.new)
                               .call(box, message: "x", review: ->(_d) {}).message, "off limits"
    assert_includes Restructure.new(repo_root: @repo, tree: "RAILS", proof: Proof.new)
                               .call(migration, message: "x", review: ->(_d) {}).message, "off limits"
  end

  def test_the_kernel_and_other_trees_are_refused
    kernel = Restructure::Plan.parse("=== WRITE MASTER/data/soul.yml\nx\n=== END\n")
    spine = Restructure::Plan.parse("=== WRITE MASTER/lib/core/mission.rb\nx\n=== END\n")

    assert_includes restructure.call(spine, message: "x", review: ->(_d) {}).message, "immutable"
    outside = Restructure::Plan.parse("=== WRITE RAILS/app.rb\nx\n=== END\n")

    assert_includes restructure.call(kernel, message: "x", review: ->(_d) {}).message, "immutable"
    assert_includes restructure.call(outside, message: "x", review: ->(_d) {}).message, "outside MASTER/"
  end
end
