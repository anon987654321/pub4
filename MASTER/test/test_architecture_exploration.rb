# frozen_string_literal: true

require_relative "test_helper"
require_relative "../lib/fix/architecture_exploration"
require "tmpdir"
require "fileutils"
require "json"

class TestArchitectureExploration < Minitest::Test
  class FakeAgent
    attr_reader :prompts
    def initialize(reply)
      @reply = reply
      @prompts = []
    end
    def ask_once(prompt)
      @prompts << prompt
      @reply
    end
  end

  def test_candidate_count_is_bounded_to_thirty_through_forty
    assert_equal 40, Master::Fix::ArchitectureExploration.candidate_count({ "MASTER_FIX_ARCHITECTURE_CANDIDATES" => "99" })
    assert_equal 30, Master::Fix::ArchitectureExploration.candidate_count({ "MASTER_FIX_ARCHITECTURE_CANDIDATES" => "3" })
    assert_equal 36, Master::Fix::ArchitectureExploration.candidate_count({})
    assert_equal 40, Master::Fix::ArchitectureExploration::LENSES.size
  end

  def test_only_repository_root_and_exact_top_level_trees_are_eligible
    Dir.mktmpdir("architecture-targets") do |root|
      %w[MASTER RAILS OPENBSD STUDIO].each { |name| Dir.mkdir(File.join(root, name)) }
      Dir.mkdir(File.join(root, "RAILS", "brgen"))
      eligible = Master::Fix::ArchitectureExploration.eligible_targets(root: root, target: root)
      assert_equal %w[MASTER RAILS OPENBSD STUDIO], eligible.map { |path| File.basename(path) }
      assert_equal ["MASTER"], Master::Fix::ArchitectureExploration.eligible_targets(
        root: root, target: File.join(root, "MASTER")
      ).map { |path| File.basename(path) }
      assert_empty Master::Fix::ArchitectureExploration.eligible_targets(
        root: root, target: File.join(root, "RAILS", "brgen")
      )
    end
  end

  def test_evidence_scored_tournament_selects_from_thirty_distinct_plans_and_marks_tests_unrun
    Dir.mktmpdir("architecture-tournament") do |root|
      master = File.join(root, "MASTER")
      FileUtils.mkdir_p(File.join(master, "lib"))
      FileUtils.mkdir_p(File.join(master, "test"))
      source_file = File.join(master, "lib", "owner.rb")
      test_file = File.join(master, "test", "test_owner.rb")
      File.write(source_file, "module Owner; end\n")
      File.write(test_file, "# regression contract\n")
      source = "MASTER/lib/owner.rb"
      test = "MASTER/test/test_owner.rb"
      candidates = Master::Fix::ArchitectureExploration::LENSES.first(30).map.with_index do |lens, i|
        { id: lens.fetch(:id), lens: lens.fetch(:name),
          title: "Architecture option variantmark#{i}",
          thesis: "Try #{lens.fetch(:name)} with uniquehypothesismark#{i} preserving local ownership.",
          core_boundary: "Boundary pivotmark#{i} assigns one lifecycle owner.",
          change_paths: [source, "MASTER/lib/new_boundary_#{i}.rb"],
          evidence_paths: [source], test_paths: [test],
          verification_plan: "Run ruby -Itest #{test} and assert regression baseline #{i}.",
          rollback_plan: "Use git revert of the isolated commit and restore the known-good boundary.",
          law_alignment: "Preserve existing behavior, constitutional Laws and operator-owned values.",
          risks: ["Migration risk #{i}"] }
      end
      agent = FakeAgent.new(JSON.generate(candidates: candidates))
      explorer = Master::Fix::ArchitectureExploration.new(root: root, agent: agent, candidate_count: 30)
      result = explorer.run(target: master, files: [source_file, test_file])
      assert_equal "COMPLETE", result.fetch("status")
      report = result.fetch("targets").first
      assert_equal 30, report.fetch("accepted")
      assert_equal 30, report.fetch("requested")
      assert_equal "NOT_RUN", report.fetch("winner").fetch("runtime_tests")
      assert_operator report.fetch("winner").fetch("score"), :>, 50
      assert_equal 5, report.fetch("shortlist").size
      assert_equal 1, agent.prompts.size
      assert_includes agent.prompts.first, "PLAN ONLY"
    end
  end

  def test_missing_or_unusable_candidates_are_inconclusive
    Dir.mktmpdir("architecture-inconclusive") do |root|
      master = File.join(root, "MASTER")
      FileUtils.mkdir_p(File.join(master, "lib"))
      source_file = File.join(master, "lib", "owner.rb")
      File.write(source_file, "module Owner; end\n")
      agent = FakeAgent.new(JSON.generate(candidates: []))
      explorer = Master::Fix::ArchitectureExploration.new(root: root, agent: agent, candidate_count: 30)
      report = explorer.run(target: master, files: [source_file]).fetch("targets").first
      assert_equal "INCONCLUSIVE", report.fetch("status")
      assert_nil report.fetch("winner")
      assert_equal 0, report.fetch("accepted")
    end
  end
end
