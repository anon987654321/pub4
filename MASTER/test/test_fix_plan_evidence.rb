# frozen_string_literal: true

require_relative "test_helper"
require "tmpdir"
require_relative "../lib/fix/fix_plan"
require_relative "../lib/fix/run_journal"

class TestFixPlanEvidence < Minitest::Test
  LawStub = Struct.new(:id)
  RUNTIME_FILES = Master::Fix::FixPlan::RUNTIME_FILES

  def setup
    @root = Dir.mktmpdir("fix_plan_evidence")
    @ruby = File.join(@root, "sample.rb")
    @docs = File.join(@root, "README.md")
    File.write(@ruby, "puts :ok\n")
    File.write(@docs, "# Evidence\n")
    FileUtils.mkdir_p(File.join(@root, "MASTER", "data"))
    File.write(File.join(@root, "MASTER", "data", "soul.yml"), "schema: 1\n")
    File.write(File.join(@root, "MASTER", "data", "laws.yml"), "laws: []\n")
    RUNTIME_FILES.each do |relative|
      path = File.join(@root, "MASTER", relative)
      FileUtils.mkdir_p(File.dirname(path))
      File.write(path, "# fixture: #{relative}\n") unless File.exist?(path)
    end
  end

  def teardown
    FileUtils.remove_entry(@root) if @root && Dir.exist?(@root)
  end

  def capture(files: [@ruby, @docs], laws: [LawStub.new("ROBUSTNESS")],
               adapters: { whole_file: "registered" }, excluded_paths: {})
    Master::Fix::FixPlan.capture(
      root: @root,
      target: @root,
      files:,
      laws:,
      excluded: {
        counts: { too_large: excluded_paths.size },
        paths: excluded_paths,
        sample: excluded_paths.keys.sort.first(20),
      },
      adapters:,
      max_passes: 15,
      budget_seconds: 120,
    )
  end

  def test_plan_pins_scope_provenance_authority_law_runtime_toolchain_and_deadline
    plan = capture(excluded_paths: { "large.rb" => "too_large" })

    assert plan.frozen?
    assert_equal %w[README.md sample.rb], plan.sources.map(&:path)
    assert_equal 2, plan.to_h.fetch("eligible_files")
    assert_match(/\A[0-9a-f]{64}\z/, plan.source_digest)
    assert_match(/\A[0-9a-f]{64}\z/, plan.law_digest)
    assert_match(/\A[0-9a-f]{64}\z/, plan.law_source_digest)
    assert_match(/\A[0-9a-f]{64}\z/, plan.authority_digest)
    assert_match(/\A[0-9a-f]{64}\z/, plan.toolchain_digest)
    assert_match(/\A[0-9a-f]{64}\z/, plan.exclusion_digest)
    assert_match(/\A[0-9a-f]{64}\z/, plan.digest)
    assert_equal "registered", plan.adapters.fetch("whole_file")
    assert_equal ["large.rb"], plan.excluded.fetch("sample")
    assert_match(/\A[0-9a-f]{64}\z/, plan.excluded.fetch("paths_digest"))
    assert plan.deadline_at.end_with?("Z")
  end

  def test_plan_and_nested_manifest_are_immutable
    plan = capture
    assert_raises(FrozenError) { plan.sources << plan.sources.first }
    assert_raises(FrozenError) { plan.to_h.fetch("adapters")["whole_file"] = "fake" }
    assert_raises(FrozenError) { plan.excluded.fetch("counts")["too_large"] = 0 }
  end

  def test_source_change_advances_generation_digest_but_preserves_identity
    first = capture
    File.write(@ruby, "puts :changed\n")
    second = capture

    assert_equal first.scope_digest, second.scope_digest
    assert_equal first.identity_digest, second.identity_digest
    refute_equal first.source_digest, second.source_digest
    refute_equal first.digest, second.digest
  end

  def test_scope_law_authority_and_exclusion_changes_change_identity
    first = capture
    File.write(File.join(@root, "other.rb"), "puts :other\n")
    expanded = capture(files: [@ruby, @docs, File.join(@root, "other.rb")])
    reauthored = capture(laws: [LawStub.new("SECURITY")])
    File.write(File.join(@root, "MASTER", "data", "laws.yml"), "laws: [SECURITY]\n")
    authority_changed = capture
    excluded_changed = capture(excluded_paths: { "large.rb" => "too_large" })

    refute_equal first.scope_digest, expanded.scope_digest
    refute_equal first.identity_digest, expanded.identity_digest
    refute_equal first.law_digest, reauthored.law_digest
    refute_equal first.identity_digest, reauthored.identity_digest
    refute_equal first.authority_digest, authority_changed.authority_digest
    refute_equal first.exclusion_digest, excluded_changed.exclusion_digest
  end

  def test_plan_rejects_paths_outside_its_repository_root
    outside = File.join(Dir.tmpdir, "fix-plan-outside-#{Process.pid}.rb")
    File.write(outside, "puts :outside\n")
    assert_raises(ArgumentError) { capture(files: [outside]) }
  ensure
    File.delete(outside) if outside && File.exist?(outside)
  end

  def test_plan_rejects_empty_or_blank_law_identity
    assert_raises(ArgumentError) { capture(laws: []) }
    assert_raises(ArgumentError) { capture(laws: [LawStub.new(" ")]) }
  end

  def test_journal_invalidates_convergence_when_source_generation_changes
    journal = Master::Fix::RunJournal.new(root: @root)
    run = journal.start_or_resume(target: @root, files: [@ruby], max_passes: 5, budget_seconds: 120)
    first = capture(files: [@ruby])
    first_binding = journal.bind_plan(run.fetch("id"), first)

    refute first_binding.fetch(:invalidated)
    assert_equal 0, first_binding.fetch(:generation)
    journal.save_convergence_state(
      run.fetch("id"),
      { "version" => 1, "source_digest" => first.source_digest },
      pass_state: { "version" => 1, "consecutive_clean" => 2 },
    )

    File.write(@ruby, "puts :changed\n")
    second = capture(files: [@ruby])
    second_binding = journal.bind_plan(run.fetch("id"), second)

    assert second_binding.fetch(:invalidated)
    assert_includes second_binding.fetch(:dimensions), "source_digest"
    assert_equal 1, second_binding.fetch(:generation)
    saved = journal.history.find { |row| row["id"] == run.fetch("id") }
    refute saved.key?("convergence_state")
    refute saved.key?("pass_state")
    assert_equal second.source_digest, saved.dig("plan", "source_digest")
  end
end
