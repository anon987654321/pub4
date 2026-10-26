# frozen_string_literal: true

require "json"
require "minitest/autorun"
require "tmpdir"
require "fileutils"
require_relative "../lib/master"
require_relative "../lib/fix/protocol"

class TestFixProtocol < Minitest::Test
  def test_structural_delivery_paths_share_fix_safety_and_delivery_contracts
    restructure = File.read(File.join(Master::ROOT, "lib/fix/restructure.rb"), encoding: "UTF-8")
    rename = File.read(File.join(Master::ROOT, "lib/fix/file_rename.rb"), encoding: "UTF-8")
    fix_loop = File.read(File.join(Master::ROOT, "lib/fix/fix_loop.rb"), encoding: "UTF-8")

    [restructure, rename].each do |source|
      assert_includes source, "Operator::RatchetSponsor.validate!"
      assert_includes source, "Ground::PreserveUserIntent"
      assert_includes source, "@ground_truth"
      assert_includes source, "@git.push"
      assert_includes source, "@known_good.promote!"
      assert_includes source, "delivery pending"
    end
    assert_includes fix_loop, "ground_truth:, preserve_user_intent:"
  end

  def test_instruction_distinguishes_fix_from_dry_run
    text = Master::Fix::Protocol.instruction.gsub(/\s+/, " ")

    assert_includes text, "/fix and --dry-run are distinct"
    assert_includes text, "lexical_violations"
    assert_includes text, "semantic_opportunities"
    assert_includes text, "two consecutive evidence-backed clean readings"
    assert_includes text, "No deterministic fixer exists"
    assert_includes text, "complete current source"
    assert_includes text, "complete current source of every direct dependency"
    assert_includes text, "30–40 materially distinct architecture"
    assert_includes text, "at least three plans passing the deterministic quality"
    assert_includes text, "concrete benefits, trade-offs and risks"
    assert_includes text, "MASTER/data/ux_refinements.yml"
    assert_includes text, "generated documentation"
    assert_includes text, "commit and push"
    assert_includes text, "Never promise that literally every defect was repaired"
  end

  def test_practice_laws_name_full_source_docs_and_verified_checkpoint_contracts
    require File.join(Master::ROOT, "law", "definition") unless defined?(::Law)
    ::Law.load_all(File.join(Master::ROOT, "law")) if ::Law.definitions.empty?

    preserve = ::Law.definitions.fetch(:PRESERVE_FIRST)
    docs = ::Law.definitions.fetch(:DOCUMENTATION_FOLLOWS_CODE)
    execute = ::Law.definitions.fetch(:EXECUTE_NOT_INSTRUCT)

    assert_match(/complete current target/i, preserve.practice)
    assert_match(/canonical generator/i, docs.practice)
    assert_match(/commit and push each owned/i, execute.practice.gsub(/\s+/, " "))
  end

  def test_external_context_carries_the_cross_tree_operating_model
    Dir.mktmpdir("fix-context") do |root|
      FileUtils.mkdir_p(File.join(root, "RAILS"))
      FileUtils.mkdir_p(File.join(root, "OPENBSD", "data"))
      File.write(File.join(root, "RAILS", "CLAUDE.md"), "rails contract\n")
      File.write(File.join(root, "RAILS", "apps.yml"), "apps:\n  brgen:\n    domain: brgen.no\n    port: 38182\n")
      File.write(File.join(root, "OPENBSD", "RUNBOOK.md"), "runbook\n")
      File.write(File.join(root, "OPENBSD", "data", "operator.yml"), "meta:\n  source: runtime authority\n")
      File.write(
        File.join(root, "OPENBSD", "deploy_inventory.json"),
        '{"apps":[{"name":"brgen","domain":"brgen.no","port":38182}],"master_face":{"domain":"ai.brgen.no","port":53187}}',
      )

      context = Master::Fix::Protocol.context(root:, target: File.join(root, "OPENBSD"))

      assert_includes context, "OPERATING MODEL"
      assert_includes context, "feature_truth=RAILS/apps.yml"
      assert_includes context, "deploy_identity=OPENBSD/deploy_inventory.json"
      assert_includes context, "evidence_ladder: source authority → executable proof → live evidence"
      assert_includes context, "cross-tree proof law: identify the authority"
      assert_includes context, '"target": "OPENBSD"'
    end
  end

  def test_render_uses_the_canonical_law_contract_digest
    Dir.mktmpdir("fix-protocol-digest") do |root|
      File.write(File.join(root, "thing.rb"), "puts :ok\n")

      payload = JSON.parse(Master::Fix::Protocol.render(root:, target: root))

      assert_equal Law::Contract.digest, payload.fetch("law_digest")
    end
  end

  def test_render_exposes_applicable_law_selection
    Dir.mktmpdir("fix-protocol-laws") do |root|
      target = File.join(root, "thing.rb")
      File.write(target, "puts :ok\n")

      payload = JSON.parse(Master::Fix::Protocol.render(root:, target:))
      application = payload.fetch("law_application")

      assert_equal "ruby", application.fetch("language")
      assert_includes application.fetch("governing_laws"), "SINGULARITY"
      assert_includes application.fetch("executable_laws"), "FROZEN_STRING_LITERAL"
    end
  end

  def test_law_metadata_exposes_machine_readable_repair_and_verification
    law = Master::Fix::Protocol.laws.find(&:semantic?)

    refute_nil law
    entry = Master::Fix::Protocol.law_entry(law)

    assert entry.key?("fix_strategy")
    assert entry.key?("verify_strategy")
    assert entry.key?("enforcement")
    assert_equal "semantic_model_repair", entry.fetch("fix_strategy")
  end

  def test_strategy_decision_tree_covers_all_four_paths
    strategy = Class.new do
      attr_reader :practice

      def initialize(semantic:, practice:, detector:)
        @semantic = semantic
        @practice = practice
        @detector = detector
      end

      def semantic? = @semantic
      def scannable? = @detector
    end

    semantic = strategy.new(semantic: true, practice: "work guidance", detector: true)
    practice = strategy.new(semantic: false, practice: "work guidance", detector: false)
    detector = strategy.new(semantic: false, practice: "", detector: true)
    residual = strategy.new(semantic: false, practice: "", detector: false)

    protocol = Master::Fix::Protocol

    assert_equal "semantic_model_repair", protocol.strategy_for(semantic)
    assert_equal "semantic_rescan_plus_behavior_or_test", protocol.verification_for(semantic)

    assert_equal "conduct_only", protocol.strategy_for(practice)
    assert_equal "manual_conduct_evidence", protocol.verification_for(practice)

    assert_equal "deterministic_or_ast_or_model_repair", protocol.strategy_for(detector)
    assert_equal "law_rescan_plus_behavior_or_test", protocol.verification_for(detector)

    assert_equal "model_or_human_analysis", protocol.strategy_for(residual)
    assert_equal "law_rescan_plus_behavior_or_test", protocol.verification_for(residual)
  end

  def test_render_has_live_corpus_and_terminal_states
    Dir.mktmpdir("fix-protocol") do |root|
      File.write(File.join(root, "thing.rb"), "puts :ok\n")

      payload = JSON.parse(Master::Fix::Protocol.render(root:, target: root))

      assert_equal 6, Master::Fix::Protocol::VERSION
      assert_equal Master::Fix::Protocol::VERSION, payload.fetch("fix_protocol_version")
      assert_includes payload.fetch("stages"), "semantic"
      assert_includes payload.fetch("terminal_states"), "PLATEAU"
      assert_includes payload.fetch("terminal_states"), "INCONCLUSIVE"
      assert_equal 1, payload.dig("corpus", "total_regular_files")
      assert_kind_of Hash, payload.fetch("detector_matrix")
      assert_kind_of Hash, payload.fetch("detector_summary")
      assert_equal payload.fetch("detector_matrix").size,
                   payload.dig("detector_summary", "total_laws")
    end
  end

  def test_render_exposes_four_stream_contract_without_claiming_it_was_measured
    Dir.mktmpdir("fix-protocol-four-streams") do |root|
      File.write(File.join(root, "thing.rb"), "puts :ok\n")
      payload = JSON.parse(Master::Fix::Protocol.render(root:, target: root))
      contract = payload.fetch("assessment_contract")

      assert_equal Master::Fix::FourStreamAssessment::STREAMS.map(&:to_s), contract.fetch("streams")
      assert_equal Master::Fix::FourStreamAssessment::SURFACES.map(&:to_s), contract.fetch("surfaces")
      assert_equal "contract_only_not_measurement", contract.fetch("runtime_status")
      assert_equal 2, contract.fetch("clean_passes_required")
      exploration = payload.fetch("architecture_exploration_contract")
      assert_equal 36, exploration.fetch("default_candidates_per_tree")
      assert_equal 30, exploration.fetch("minimum_candidates_for_selection")
      assert_equal 40, exploration.fetch("maximum_candidates_per_tree")
      assert_equal 65, exploration.dig("quality_gate", "minimum_score")
      assert_equal 3, exploration.dig("quality_gate", "minimum_qualified_candidates")
      assert_includes exploration.fetch("required_consequence_fields"), "tradeoffs"
      assert_equal "NOT_RUN until actual tree verification commands execute", exploration.fetch("execution_evidence")
      assert_equal 90, payload.dig("ux_refinement_catalog", "loaded_count")
      assert_equal 90, payload.dig("ux_refinement_catalog", "expected_count")
      assert_equal 90, payload.dig("ux_refinement_catalog", "acceptance_required_count")
    end
  end

  def test_render_exposes_truthful_capability_boundaries
    Dir.mktmpdir("fix-protocol-capabilities") do |root|
      File.write(File.join(root, "thing.rb"), "puts :ok\n")

      payload = JSON.parse(Master::Fix::Protocol.render(root:, target: root))
      report = payload.fetch("capability_report")

      assert_kind_of Array, report.fetch("measurement_only_detectors")
      assert_kind_of Array, report.fetch("advisory_laws")
      assert_kind_of Array, report.fetch("semantic_laws_without_deterministic_detector")
      coverage = report.fetch("four_stream_law_coverage")
      assert_equal "declared_reach_complete", coverage.fetch("declaration_status")
      assert_equal 0, coverage.fetch("streams").fetch("semantic_violations").fetch("missing_count")
      assert_equal 0, coverage.fetch("streams").fetch("semantic_opportunities").fetch("missing_count")
      assert_equal "not_measured", coverage.fetch("runtime_status")
      assert_equal "not_measured", report.fetch("verification_runtime")
    end
  end

  def test_incremental_done_requires_full_scope_verification
    source = File.read(File.join(Master::ROOT, "lib/fix/fix_loop/lifecycle.rb"), encoding: "UTF-8")
    start = source.index("def verify_incremental_scope")
    finish = source.index("def mission_for", start)
    refute_nil start
    refute_nil finish
    check = source[start...finish]

    assert_includes check, "terminal_state_for(result) == :done"
    assert_includes check, "@file_collector.collect(target)"
    assert_includes check, "blocking_skips"
    assert_includes check, "@reachability.verify!(target, files: full_files)"
    assert_includes check, "@convergence_discipline.begin_run(full_files, preserve_run_baseline: true)"
    assert_includes check, "CLEAN_RUNS"
  end

end
