# frozen_string_literal: true

require "minitest/autorun"
require "date"
require "yaml"
require "pathname"

class TestRecoveryPubManifest < Minitest::Test
  ROOT = Pathname(__dir__).join("..", "..").expand_path

  # The contract this pins is which files exist, so it is the file most able to
  # pin the wrong ones. It arrived naming two under DEPLOY/, a tree this repo
  # renamed away — asserting them would have made a green test the reason the
  # tree came back.
  def test_restore_docs_exist
    # The prose halves are gone. RESTORE_FROM_PUB.md and the three RECOVERY/
    # READMEs restated in 905 lines what the manifest below already holds as
    # structured rows — a source, a state, and a reason per entry — and they
    # opened by dating themselves to a layout this repo had already renamed.
    # The ledger is what the contract needs; git holds the prose.
    required = [
      "MASTER/data/recovery/legacy_manifest.yml",
      "MASTER/data/recovery/plugin_schema_v1.json",
      "MASTER/data/recovery_pub.yml",
    ]

    missing = required.reject { |path| ROOT.join(path).file? }
    assert_empty missing, "missing recovery files: #{missing.join(", ")}"
  end

  def test_recovery_contract_has_critical_items
    contract = YAML.safe_load(ROOT.join("MASTER/data/recovery_pub.yml").read, permitted_classes: [Date])
    ids = contract.fetch("critical_items").map { |item| item.fetch("id") }

    assert_includes ids, "mega_all_apps"
    assert_includes ids, "ai3_standalone"
    assert_includes ids, "bplans_pipeline"
    assert_includes ids, "privcam_active_decision"
  end

  def test_legacy_manifest_has_state_definitions
    manifest = YAML.safe_load(ROOT.join("MASTER/data/recovery/legacy_manifest.yml").read, permitted_classes: [Date])
    states = manifest.fetch("states")

    %w[restored ported absorbed archived missing partial retired].each do |state|
      assert states.key?(state), "state #{state} must be defined"
    end
  end

  def test_legacy_manifest_uses_declared_states
    manifest = YAML.safe_load(ROOT.join("MASTER/data/recovery/legacy_manifest.yml").read, permitted_classes: [Date])
    declared = manifest.fetch("states").keys
    used = manifest.fetch("legacy_roots").filter_map { |item| item["state"] }
    used.concat(manifest.fetch("rails_restore_debt").values.filter_map { |item| item["state"] })

    invalid = used.uniq.reject { |state| declared.include?(state) }
    assert_empty invalid, "undeclared recovery states: #{invalid.join(", ")}"
  end

  def test_archive_inventory_has_one_record_per_generation
    manifest = YAML.safe_load(ROOT.join("MASTER/data/recovery/legacy_manifest.yml").read, permitted_classes: [Date])
    inventory = manifest.fetch("archive_inventory").fetch("repositories")

    %w[pub pub2 pub3 pub4].each do |repo|
      entry = inventory.fetch(repo)
      %w[tracked_archives unique_blobs compressed_bytes paths].each do |key|
        assert entry.key?(key), "#{repo} archive inventory needs #{key}"
      end
    end

    pub = inventory.fetch("pub")
    assert_equal 157, pub.fetch("tracked_archives")
    assert_equal 122, pub.fetch("unique_blobs")
    assert_equal 35, manifest.fetch("archive_duplicate_summary").fetch("pub").fetch("duplicate_paths")
  end

  def test_historical_refs_keep_the_unmerged_lines_visible
    manifest = YAML.safe_load(ROOT.join("MASTER/data/recovery/legacy_manifest.yml").read, permitted_classes: [Date])
    refs = manifest.fetch("repository_refs")

    assert_equal(
      "d1f2770fc43fd0e85e9d640d71e9b0748fd9712e",
      refs.dig("pub3", "branches", "my-work")
    )
    assert_equal(
      "8953b9f9ebc394a4901448fb20369f1c00d1b895",
      refs.dig("pub2", "branches", "copilot/canonicalize-configuration-files")
    )
    assert_equal(
      "468b313046236cd0898c5758edc019ef87923a5c",
      refs.dig("pub", "branches", "restructure-consolidation")
    )
  end

  def test_archaeology_records_preserve_disposition
    manifest = YAML.safe_load(ROOT.join("MASTER/data/recovery/legacy_manifest.yml").read, permitted_classes: [Date])

    manifest.fetch("mass_change_reviews").each do |review|
      assert review["repo"]
      assert review["commit"]
      assert review["finding"]
      assert review["disposition"]
    end

    manifest.fetch("reversion_reviews").each do |review|
      assert review["repo"]
      assert review["commit"]
      assert review["finding"]
      assert review["disposition"]
    end
  end

  def test_master_json_lineage_is_evidence_not_a_second_authority
    manifest = YAML.safe_load(ROOT.join("MASTER/data/recovery/legacy_manifest.yml").read, permitted_classes: [Date])
    lineage = manifest.fetch("master_json_lineage").fetch("pub3_my_work")

    assert_equal "50.0.0", lineage.fetch("version")
    assert_includes lineage.fetch("preserve"), "ask-before-act / drift / hardcoded-paths / unhandled-edge"
    assert_includes lineage.fetch("caution"), "The v50 file predates current pub4 law migration and is evidence, not a second constitution."
  end

  def test_legacy_manifest_has_no_duplicate_top_level_keys
    lines = ROOT.join("MASTER/data/recovery/legacy_manifest.yml").read.each_line
    keys = lines.filter_map do |line|
      match = line.match(/\A([A-Za-z_][A-Za-z0-9_-]*):(?:\s|$)/)
      match && match[1]
    end

    duplicates = keys.tally.select { |_key, count| count > 1 }.keys
    assert_empty duplicates, "duplicate top-level recovery keys: #{duplicates.join(", ")}"
  end
  def test_master2_and_face_reviews_are_explicitly_dispositioned
    manifest = YAML.safe_load(ROOT.join("MASTER/data/recovery/legacy_manifest.yml").read, permitted_classes: [Date])
    master2 = manifest.fetch("master2_lineage")
    assert_includes master2.fetch("retained_semantics"), "Keep workflow lifecycle explicit and observable, but do not reinflate the retired eight-phase MASTER2 state machine."

    openbsd = manifest.fetch("legacy_cli_reviews").fetch("openbsd_commands")
    assert_equal "retired-unsafe", openbsd.fetch("disposition")

    face = manifest.fetch("legacy_cli_reviews").fetch("face_branch")
    assert_equal "retired-by-consolidation", face.fetch("disposition")

    v43 = manifest.fetch("master_json_v43_review")
    assert_equal "semantic-recovery-only", v43.fetch("disposition")
    assert_includes v43.fetch("not_restored"), "The old prediction_engine confidence-based autonomous mutation policy."
  end
  def test_accidental_collapse_recovery_is_pinned
    manifest = YAML.safe_load(ROOT.join("MASTER/data/recovery/legacy_manifest.yml").read, permitted_classes: [Date])
    recovery = manifest.fetch("mass_recovery_reviews").fetch("pub4_accidental_collapse")
    assert_equal "b4c510ef96eac87cfa6ca946fd30f530f8c5c8a0", recovery.fetch("recovery_commit")
    assert_equal 5507, recovery.fetch("restored_tree_entries")
    assert_equal 6, recovery.fetch("recovery_changes_vs_pre_collapse")
    assert_equal "recovery-authoritative", recovery.fetch("disposition")
  end
  def test_legacy_capability_reviews_are_explicit
    manifest = YAML.safe_load(ROOT.join("MASTER/data/recovery/legacy_manifest.yml").read, permitted_classes: [Date])

    aight = manifest.fetch("legacy_capability_reviews").fetch("pub3_aight")
    assert_includes aight.fetch("absorbed").map { |item| item.fetch("capability") }, "memory, context and session lifecycle"
    assert_equal "partial; recover individual useful commands only when demanded by current MASTER workflow", aight.fetch("partial").first.fetch("disposition")
    assert_equal "retired-by-architecture", aight.fetch("retired").first.fetch("disposition")

    face = manifest.fetch("legacy_capability_reviews").fetch("pub4_face_legacy")
    assert_equal "retired-by-consolidation; do-not-restore-duplicate-renderers", face.fetch("disposition")
    assert_equal "behavioral-reference-only; candidate for selective migration only if the canonical renderer needs kinetic-depth evidence", face.fetch("notable_fossil").fetch("disposition")

    assert_equal "absorbed; do-not-restore-pub3-multimedia-dilla-tree", manifest.fetch("legacy_capability_reviews").fetch("pub4_dilla_lineage").fetch("disposition")
  end

  def test_recovered_regressions_have_a_current_disposition
    manifest = YAML.safe_load(ROOT.join("MASTER/data/recovery/legacy_manifest.yml").read, permitted_classes: [Date])
    reviews = manifest.fetch("recovered_regression_reviews")

    assert_equal 13, reviews.size
    reviews.each do |review|
      assert review["commit"]
      assert review["area"]
      assert review["finding"]
      assert review["current_mapping"]
      assert review["disposition"]
    end

    assert_equal(
      "preserved-fix",
      reviews.find { |review| review["commit"] == "d1f6a31af0c82d8f6127b60eabbc76eef0cdef81" }.fetch("disposition")
    )
    assert_equal(
      "deferred-gap; recover only if mixed-language parsing becomes an actual current requirement",
      reviews.find { |review| review["commit"] == "97a761812e9b814188f702528cd47d09dddb6cdc" }.fetch("disposition")
    )
  end

  def test_legacy_deploy_bundle_is_reconciled
    manifest = YAML.safe_load(ROOT.join("MASTER/data/recovery/legacy_manifest.yml").read, permitted_classes: [Date])
    review = manifest.fetch("legacy_deploy_bundle_review")

    assert_equal "41dcb7c8a88ada5ab948d0fd65e222ed3683d037", review.fetch("restoration_commit")
    assert_equal "246160caaaf7d96930395d5a8e8bd19c8096ce0c", review.fetch("pruning_commit")
    assert_equal 6, review.fetch("retained_patterns").size
    assert_equal "Keep the Git commits as provenance; do not resurrect the script forest. Rebuild any missing behavior inside current app/shared boundaries.",
                 review.fetch("archive_rule")
  end

  def test_late_archaeology_records_are_pinned
    manifest = YAML.safe_load(ROOT.join("MASTER/data/recovery/legacy_manifest.yml").read, permitted_classes: [Date])

    dilla = manifest.fetch("pub2_dilla_carousel_review")
    assert_equal "absorbed; do-not-restore-html-monolith", dilla.fetch("disposition")

    gaps = manifest.fetch("deferred_semantic_gaps")
    assert gaps.any? { |gap| gap["capability"] == "encrypted session persistence" }
    assert gaps.any? { |gap| gap["capability"] == "mixed-language heredoc parser" }

    ai3 = manifest.fetch("legacy_ai3_role_review")
    assert_includes ai3.fetch("roles_with_nontrivial_surface").map { |role| role.fetch("role") }, "legal"
    assert_includes ai3.fetch("excluded_as_runtime"), "external Weaviate/Ferrum-backed autonomous assistant trees"
  end

  def test_pub_backup_plan_is_reconciled_to_current_rails_tree
    manifest = YAML.safe_load(ROOT.join("MASTER/data/recovery/legacy_manifest.yml").read, permitted_classes: [Date])
    review = manifest.fetch("pub_backup_restoration_plan_review")

    assert_equal "18d9bbbc63121aedfedd2366f540b8ee56006674", review.fetch("source_commit")
    assert_equal 9, review.fetch("archive_set").size
    assert_equal 8, review.fetch("reconciled_surfaces").size
    assert review.fetch("reconciled_surfaces").all? { |surface| surface.fetch("disposition") == "absorbed" }
    assert_includes review.fetch("unresolved_archival_apps"), "baibl: preserved in historical archive inventory; not an active app decision in current pub4."
  end

  def test_pub2_reasoning_lineage_is_absorbed_without_a_second_authority
    manifest = YAML.safe_load(ROOT.join("MASTER/data/recovery/legacy_manifest.yml").read, permitted_classes: [Date])
    lineage = manifest.fetch("pub2_semantic_lineage")

    assert_equal "absorbed-semantic", lineage.dig("reasoning_framework_v135", "disposition")
    assert_equal "absorbed-semantic", lineage.dig("canonical_v20_2", "disposition")
    assert_includes lineage.dig("reasoning_framework_v135", "value"), "questions before solutions"
    assert_includes lineage.dig("canonical_v20_2", "value"), "ask before destructive action"
    assert_includes lineage.fetch("caution"), "The old JSON versions are historical reasoning evidence, not runtime configuration."
  end
  def test_missing_until_restored_contains_only_absent_targets
    contract = YAML.safe_load(ROOT.join("MASTER/data/recovery_pub.yml").read, permitted_classes: [Date])
    paths = contract.fetch("checks").fetch("missing_until_restored")
    present = paths.select { |path| ROOT.join(path).file? }

    assert_empty present, "recovery ledger marks present paths as missing: #{present.join(", ")}"
  end
end
