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
end
