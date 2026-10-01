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

    %w[restored ported absorbed archived missing retired].each do |state|
      assert states.key?(state), "state #{state} must be defined"
    end
  end
end
