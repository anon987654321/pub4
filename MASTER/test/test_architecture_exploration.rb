# frozen_string_literal: true

require_relative "test_helper"
require_relative "../lib/fix/architecture_exploration"
require "tmpdir"
require "fileutils"
require "json"

class TestArchitectureExploration < Minitest::Test
  class FakeJournal
    attr_reader :writes

    def initialize
      @writes = []
      @report = nil
      @provenance = nil
    end

    def verify_architecture_report(_run_id)
      return { "status" => "receipt_missing" } unless @report

      { "status" => "verified", "report" => @report, "provenance" => @provenance }
    end

    def seed_report(report, provenance)
      @report = JSON.parse(JSON.generate(report))
      @provenance = JSON.parse(JSON.generate(provenance))
    end

    def persist_architecture_report(_run_id, target:, report:, provenance:)
      @report = JSON.parse(JSON.generate(report))
      @provenance = JSON.parse(JSON.generate(provenance))
      @writes << { "target" => target.to_s, "status" => report.fetch("status"),
                   "targets" => @report.fetch("targets").size,
                   "accepted" => @report.fetch("targets").sum { |row| row.fetch("accepted", 0).to_i } }
      { "status" => "persisted", "readback_verified" => true }
    end
  end

  class FakeBus
    attr_reader :events

    def initialize
      @events = []
    end

    def publish(event, payload = {})
      @events << [event, payload]
    end
  end

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

  def test_evidence_selection_skips_unsupported_files_until_text_evidence_is_found
    Dir.mktmpdir("architecture-evidence-selection") do |root|
      master = File.join(root, "MASTER")
      FileUtils.mkdir_p(master)
      unsupported = 12.times.map do |index|
        path = File.join(master, format("%02d.png", index))
        File.write(path, "non-text asset payload")
        path
      end
      source = File.join(master, "z_owner.rb")
      File.write(source, "module Owner; end\n")
      explorer = Master::Fix::ArchitectureExploration.new(
        root: root, agent: FakeAgent.new("{}"), candidate_count: 30
      )

      evidence = explorer.send(:evidence_for, unsupported + [source])

      assert_equal ["MASTER/z_owner.rb"], evidence.map { |entry| entry.fetch("path") }
      assert_match(/\A[0-9a-f]{64}\z/, evidence.first.fetch("sha256"))
      assert_operator evidence.first.fetch("excerpt").bytesize, :<=, 800
    end
  end

  def test_evidence_selection_skips_empty_text_files_without_spending_slots
    Dir.mktmpdir("architecture-empty-evidence") do |root|
      master = File.join(root, "MASTER")
      FileUtils.mkdir_p(master)
      empty_paths = 12.times.map do |index|
        path = File.join(master, format("%02d_empty.rb", index))
        File.write(path, "")
        path
      end
      source = File.join(master, "z_owner.rb")
      File.write(source, "module Owner; end\n")
      explorer = Master::Fix::ArchitectureExploration.new(
        root: root, agent: FakeAgent.new("{}"), candidate_count: 30
      )

      evidence = explorer.send(:evidence_for, empty_paths + [source])

      assert_equal ["MASTER/z_owner.rb"], evidence.map { |entry| entry.fetch("path") }
    end
  end

  def test_evidence_excerpt_budget_is_a_byte_limit_for_utf8_text
    Dir.mktmpdir("architecture-evidence-byte-budget") do |root|
      master = File.join(root, "MASTER")
      FileUtils.mkdir_p(master)
      paths = 12.times.map do |index|
        path = File.join(master, format("%02d_owner.rb", index))
        File.write(path, "ø" * 800)
        path
      end
      explorer = Master::Fix::ArchitectureExploration.new(
        root: root, agent: FakeAgent.new("{}"), candidate_count: 30
      )

      evidence = explorer.send(:evidence_for, paths)

      assert_equal 8, evidence.size, "the 12 KB budget should retain full excerpts until the final bounded excerpt"
      assert_equal 12_000, evidence.sum { |entry| entry.fetch("excerpt").bytesize }
      assert evidence.all? { |entry| entry.fetch("excerpt").valid_encoding? }
    end
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
          benefits: ["This improves owner separation and reduces duplicate reads #{i}."],
          tradeoffs: ["Migration costs one bounded change and requires an additional regression check #{i}."],
          risks: ["Migration risk includes compatibility checks for variant #{i}"] }
      end
      agent = FakeAgent.new(JSON.generate(candidates: candidates))
      journal = FakeJournal.new
      provenance = { "source_digest" => "a" * 64, "scope_digest" => "b" * 64,
                     "law_digest" => "c" * 64, "identity_digest" => "d" * 64 }
      explorer = Master::Fix::ArchitectureExploration.new(
        root: root, agent: agent, candidate_count: 30, run_journal: journal,
        run_id: "a" * 20, provenance:
      )
      result = explorer.run(target: master, files: [source_file, test_file])
      assert_equal "COMPLETE", result.fetch("status")
      report = result.fetch("targets").first
      assert_equal 30, report.fetch("accepted")
      assert_equal 30, report.fetch("requested")
      assert_equal "NOT_RUN", report.fetch("winner").fetch("runtime_tests")
      assert_operator report.fetch("winner").fetch("score"), :>, 50
      assert_equal 5, report.fetch("shortlist").size
      decision = report.fetch("decision")
      assert_equal "local_evidence_rules", decision.fetch("scoring_authority")
      assert_equal 30, decision.fetch("distinct_change_path_sets")
      assert_equal 30, decision.fetch("qualified_candidates")
      assert decision.fetch("selection_gate_passed")
      assert_equal "NOT_RUN", decision.fetch("execution_proof")
      assert_operator decision.fetch("winner_margin"), :>=, 0
      assert_equal 1, agent.prompts.size
      assert_includes agent.prompts.first, "PLAN ONLY"
      assert_equal "COMPLETE", journal.writes.last.fetch("status")
      assert_equal 30, report.fetch("candidates").size
      refute_empty report.fetch("evidence_manifest")
      assert_equal "a" * 64, journal.verify_architecture_report("a" * 20).fetch("provenance").fetch("source_digest")

      retry_agent = FakeAgent.new("not JSON: a completed tournament should be reused")
      resumed = Master::Fix::ArchitectureExploration.new(
        root: root, agent: retry_agent, candidate_count: 30, run_journal: journal,
        run_id: "a" * 20, provenance:
      ).run(target: master, files: [source_file, test_file])
      assert_equal result.fetch("targets").first, resumed.fetch("targets").first
      assert_empty retry_agent.prompts, "matching completed evidence must resume without regenerating candidates"
    end
  end


  def test_complete_saved_row_without_a_qualified_winner_is_regenerated
    Dir.mktmpdir("architecture-invalid-complete-row") do |root|
      master = File.join(root, "MASTER")
      FileUtils.mkdir_p(File.join(master, "lib"))
      source = File.join(master, "lib", "owner.rb")
      File.write(source, "module Owner; end\n")
      journal = FakeJournal.new
      agent = FakeAgent.new("not JSON")
      explorer = Master::Fix::ArchitectureExploration.new(
        root: root, agent: agent, candidate_count: 30,
        run_journal: journal, run_id: "c" * 20
      )
      provenance = explorer.send(:provenance)
      bad_row = {
        "tree" => "MASTER", "status" => "COMPLETE", "requested" => 30,
        "accepted" => 30, "qualified" => 0, "winner" => nil, "shortlist" => [],
        "decision" => { "selection_gate_passed" => false, "qualified_candidates" => 0, "execution_proof" => "NOT_RUN" },
        "candidates" => Array.new(30) { |i| { "id" => format("AX%02d", i + 1), "score" => 0,
          "scorecard" => { "total" => 0 } } },
        "evidence_manifest" => [{ "path" => "MASTER/lib/owner.rb", "sha256" => "d" * 64, "excerpt_bytes" => 18 }]
      }
      journal.seed_report({
        "schema_version" => 2, "target" => "MASTER", "status" => "COMPLETE",
        "provenance" => provenance, "requested_candidates_per_tree" => 30,
        "targets" => [bad_row], "brief" => "invalid saved row"
      }, provenance)

      result = explorer.run(target: master, files: [source])

      assert_equal "INCONCLUSIVE", result.fetch("status")
      assert_equal 1, agent.prompts.size, "a malformed COMPLETE row must not be resumed"
    end
  end

  def test_partial_tournament_resume_reuses_completed_trees_and_finishes_only_pending_trees
    Dir.mktmpdir("architecture-partial-resume") do |root|
      %w[MASTER RAILS].each { |name| FileUtils.mkdir_p(File.join(root, name)) }
      journal = FakeJournal.new
      provenance_input = {
        "source_digest" => "a" * 64,
        "scope_digest" => "b" * 64,
        "law_digest" => "c" * 64,
        "identity_digest" => "d" * 64,
      }
      explorer = Master::Fix::ArchitectureExploration.new(
        root: root, agent: FakeAgent.new("{}"), candidate_count: 30,
        run_journal: journal, run_id: "b" * 20, provenance: provenance_input
      )
      provenance = explorer.send(:provenance)

      tree_report = lambda do |tree|
        winner = {
          "id" => "AX01", "title" => "Keep #{tree} ownership local", "score" => 82,
          "scorecard" => {
            "source_evidence" => 20, "test_anchors" => 18, "verification" => 15,
            "rollback" => 7, "scope" => 12, "law_alignment" => 5,
            "tradeoff_analysis" => 5, "total" => 82
          },
          "thesis" => "Keep one bounded owner for #{tree}.",
          "core_boundary" => "The #{tree} lifecycle remains local.",
          "evidence_paths" => ["#{tree}/lib/owner.rb"],
          "test_paths" => ["#{tree}/test/test_owner.rb"],
          "verification_plan" => "Run the existing #{tree} regression test.",
          "benefits" => ["Reduces duplicate decisions in #{tree}."],
          "tradeoffs" => ["A bounded migration requires one additional check."],
          "risks" => ["Compatibility changes need a baseline comparison."],
          "rollback_plan" => "Revert the isolated change and restore its checkpoint.",
        }
        {
          "tree" => tree, "status" => "COMPLETE", "requested" => 30,
          "accepted" => 30, "qualified" => 12,
          "decision" => {
            "distinct_change_path_sets" => 30, "qualified_candidates" => 12,
            "selection_gate_passed" => true, "winner_margin" => 3, "execution_proof" => "NOT_RUN",
          },
          "winner" => winner, "shortlist" => [winner], "rejections" => [],
          "candidates" => Array.new(30) do |i|
            card = i < 12 ? {
              "source_evidence" => 20, "test_anchors" => 18, "verification" => 15,
              "rollback" => 7, "scope" => 12, "law_alignment" => 5,
              "tradeoff_analysis" => 5, "total" => 82
            } : {
              "source_evidence" => 0, "test_anchors" => 0, "verification" => 0,
              "rollback" => 0, "scope" => 0, "law_alignment" => 0,
              "tradeoff_analysis" => 0, "total" => 0
            }
            { "id" => format("AX%02d", i + 1), "score" => card["total"],
              "scorecard" => card, "lens" => Master::Fix::ArchitectureExploration::LENSES[i][:name] }
          end,
          "evidence_manifest" => [{ "path" => "#{tree}/lib/owner.rb", "sha256" => tree == "MASTER" ? "d" * 64 : "e" * 64,
                                    "excerpt_bytes" => 18 }],
        }
      end

      # This receipt represents a process that completed MASTER then stopped
      # before it started RAILS. The report target/provenance match this run.
      saved = {
        "schema_version" => 2, "target" => ".", "status" => "RUNNING",
        "provenance" => provenance, "requested_candidates_per_tree" => 30,
        "targets" => [tree_report.call("MASTER")], "brief" => "MASTER is complete; RAILS is pending.",
      }
      journal.seed_report(saved, provenance)
      explored = []
      explorer.define_singleton_method(:explore) do |tree, _files|
        name = File.basename(tree)
        explored << name
        tree_report.call(name)
      end

      result = explorer.run(target: root, files: [])

      assert_equal "COMPLETE", result.fetch("status")
      assert_equal %w[MASTER RAILS], result.fetch("targets").map { |row| row.fetch("tree") }
      assert_equal ["RAILS"], explored, "the completed MASTER result should not be regenerated"
      assert_equal 30, result.fetch("targets").first.fetch("candidates").size
      assert_equal 30, result.fetch("targets").last.fetch("candidates").size
      assert_equal "COMPLETE", journal.writes.last.fetch("status")
    end
  end

  def test_invalid_saved_receipt_uses_a_relative_target_in_failure_telemetry
    Dir.mktmpdir("architecture-receipt-privacy") do |root|
      %w[MASTER RAILS OPENBSD STUDIO].each { |name| FileUtils.mkdir_p(File.join(root, name)) }
      journal = FakeJournal.new
      journal.define_singleton_method(:verify_architecture_report) do |_run_id|
        { "status" => "checksum_mismatch" }
      end
      bus = FakeBus.new
      agent = FakeAgent.new("this must not be asked")
      explorer = Master::Fix::ArchitectureExploration.new(
        root: root, agent: agent, bus: bus, candidate_count: 30,
        run_journal: journal, run_id: "c" * 20
      )

      result = explorer.run(target: root, files: [])

      assert_equal "INCONCLUSIVE", result.fetch("status")
      event = bus.events.find { |name, _payload| name == "fix_loop:architecture_exploration_inconclusive" }
      # The production event bus receives the same payload. An absolute workspace
      # path is not needed to understand this failure and should never be emitted.
      assert event, "an invalid saved receipt must emit an inconclusive lifecycle event"
      assert_equal ".", event.last.fetch(:target)
      refute_includes event.last.fetch(:target), root
      assert_empty agent.prompts, "tampered evidence must be refused before model work"
    end
  end

  def test_candidates_without_test_anchors_cannot_win_even_when_their_plans_are_well_formed
    Dir.mktmpdir("architecture-quality-gate") do |root|
      master = File.join(root, "MASTER")
      FileUtils.mkdir_p(File.join(master, "lib"))
      source_file = File.join(master, "lib", "owner.rb")
      File.write(source_file, "module Owner; end\n")
      source = "MASTER/lib/owner.rb"
      candidates = Master::Fix::ArchitectureExploration::LENSES.first(30).map.with_index do |lens, i|
        { id: lens.fetch(:id), lens: lens.fetch(:name),
          title: "No-test alternative variant#{i}",
          thesis: "Keep the lifecycle local with grounded change marker#{i} and stable recovery.",
          core_boundary: "Retain one local owner boundary marker#{i} and a clear rollback.",
          change_paths: [source, "MASTER/lib/plan_#{i}.rb"],
          evidence_paths: [source], test_paths: [],
          verification_plan: "Compare measurements before and after the bounded change.",
          rollback_plan: "Use git revert and restore the last known-good checkpoint.",
          law_alignment: "Preserve existing behavior, constitutional Laws and operator values.",
          benefits: ["Reduces duplicate lifecycle decisions with measurable consistency #{i}."],
          tradeoffs: ["Adds a migration step and raises short-term coordination cost #{i}."],
          risks: ["Compatibility drift must be measured against the baseline for #{i}"] }
      end
      explorer = Master::Fix::ArchitectureExploration.new(
        root: root, agent: FakeAgent.new(JSON.generate(candidates: candidates)), candidate_count: 30
      )
      report = explorer.run(target: master, files: [source_file]).fetch("targets").first
      assert_equal "INCONCLUSIVE", report.fetch("status")
      assert_equal 30, report.fetch("accepted")
      assert_equal 0, report.fetch("qualified")
      assert_nil report.fetch("winner")
      decision = report.fetch("decision")
      refute decision.fetch("selection_gate_passed")
      assert_nil decision.fetch("winner_score")
      assert_equal "NOT_RUN", decision.fetch("execution_proof")
    end
  end

  def test_symlinked_evidence_outside_the_tree_is_rejected
    Dir.mktmpdir("architecture-symlink") do |root|
      master = File.join(root, "MASTER")
      FileUtils.mkdir_p(File.join(master, "lib"))
      source_file = File.join(master, "lib", "owner.rb")
      outside = File.join(root, "outside-secret.rb")
      File.write(source_file, "module Owner; end\n")
      File.write(outside, "secret = 'must not be used as evidence'\n")
      link = File.join(master, "lib", "external_evidence.rb")
      begin
        File.symlink(outside, link)
      rescue NotImplementedError, SystemCallError
        skip "symlink creation is unavailable"
      end
      explorer = Master::Fix::ArchitectureExploration.new(root: root, agent: FakeAgent.new("{}"), candidate_count: 30)
      refute explorer.send(:inside?, link, master)
    end
  end

  def test_only_files_shown_as_source_evidence_may_ground_a_candidate
    Dir.mktmpdir("architecture-grounding") do |root|
      master = File.join(root, "MASTER")
      FileUtils.mkdir_p(File.join(master, "lib"))
      FileUtils.mkdir_p(File.join(master, "test"))
      source_file = File.join(master, "lib", "owner.rb")
      unshown_file = File.join(master, "lib", "not_in_prompt.rb")
      test_file = File.join(master, "test", "test_owner.rb")
      File.write(source_file, "module Owner; end\n")
      File.write(unshown_file, "module Unshown; end\n")
      File.write(test_file, "# regression contract\n")
      source = "MASTER/lib/owner.rb"
      unshown = "MASTER/lib/not_in_prompt.rb"
      test = "MASTER/test/test_owner.rb"
      candidates = Master::Fix::ArchitectureExploration::LENSES.first(30).map.with_index do |lens, i|
        { id: lens.fetch(:id), lens: lens.fetch(:name),
          title: "Ungrounded alternative marker#{i}",
          thesis: "Use source-grounded owner changes with a distinct proof boundary #{i}.",
          core_boundary: "Only cited source material can justify boundary #{i}.",
          change_paths: [source, "MASTER/lib/plan_#{i}.rb"],
          evidence_paths: [unshown], test_paths: [test],
          verification_plan: "Run ruby -Itest #{test} and compare the regression baseline #{i}.",
          rollback_plan: "Use git revert and restore the last known-good owner boundary.",
          law_alignment: "Preserve existing behavior, constitutional Laws and operator-owned values.",
          benefits: ["Prevents an architecture plan from relying on unshown information #{i}."],
          tradeoffs: ["The model must reason from a smaller but actually supplied evidence set #{i}."],
          risks: ["An omitted dependency requires another evidence pass before repair #{i}"] }
      end
      explorer = Master::Fix::ArchitectureExploration.new(
        root: root, agent: FakeAgent.new(JSON.generate(candidates: candidates)), candidate_count: 30
      )
      report = explorer.run(target: master, files: [source_file, test_file]).fetch("targets").first
      assert_equal "INCONCLUSIVE", report.fetch("status")
      assert_equal 0, report.fetch("accepted")
      assert_nil report.fetch("winner")
    end
  end

  def test_top_level_tree_symlink_is_not_an_eligible_target
    Dir.mktmpdir("architecture-tree-root") do |root|
      Dir.mktmpdir("architecture-external-tree") do |outside|
        begin
          File.symlink(outside, File.join(root, "MASTER"))
        rescue NotImplementedError, SystemCallError
          skip "symlink creation is unavailable"
        end
        %w[RAILS OPENBSD STUDIO].each { |name| Dir.mkdir(File.join(root, name)) }
        eligible = Master::Fix::ArchitectureExploration.eligible_targets(root: root, target: root)
        assert_equal %w[RAILS OPENBSD STUDIO], eligible.map { |path| File.basename(path) }
      end
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
