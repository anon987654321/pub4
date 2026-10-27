# frozen_string_literal: true

require_relative "test_helper"
require_relative "../lib/fix/ux_refinement_catalog"

class TestUXRefinementCatalog < Minitest::Test
  def test_catalog_contains_ninety_unique_owned_acceptance_contracts
    payload = Master::Fix::UXRefinementCatalog.load
    rows = payload.fetch("refinements")
    assert_equal 90, rows.size
    assert_equal 90, rows.map { |row| row.fetch("id") }.uniq.size
    assert_equal "UX001", rows.first.fetch("id")
    assert_equal "UX090", rows.last.fetch("id")
    assert rows.all? { |row| row.fetch("state") == "acceptance_required" }
    manifest = Master::Fix::UXRefinementCatalog.manifest
    assert_equal 90, manifest.fetch("loaded_count")
    assert_equal 90, manifest.fetch("acceptance_required_count")
    assert_equal 0, manifest.fetch("verified_count")
    assert_equal 90, manifest.fetch("by_area").values.sum
    assert_equal %w[MASTER OPENBSD RAILS STUDIO], manifest.fetch("by_owner_tree").select { |_tree, count| count.positive? }.keys.sort
    assert_equal %w[accessibility browser source terminal unit visual], manifest.fetch("by_proof_type").keys.sort
    assert_equal 64, manifest.fetch("sha256").length
  end

  def test_catalog_requires_versioned_metadata_and_real_evidence_policy
    payload = Master::Fix::UXRefinementCatalog.load

    wrong_schema = Marshal.load(Marshal.dump(payload))
    wrong_schema["schema"] = 2
    assert_raises(ArgumentError) { Master::Fix::UXRefinementCatalog.validate!(wrong_schema) }

    wrong_authority = Marshal.load(Marshal.dump(payload))
    wrong_authority["authority"] = "MASTER/data/laws.yml#does_not_exist"
    assert_raises(ArgumentError) { Master::Fix::UXRefinementCatalog.validate!(wrong_authority) }

    weakened_policy = Marshal.load(Marshal.dump(payload))
    weakened_policy.fetch("evidence_policy")["no_simulation"] = "A checklist may stand in for runtime proof."
    assert_raises(ArgumentError) { Master::Fix::UXRefinementCatalog.validate!(weakened_policy) }
  end

  def test_catalog_rejects_missing_or_duplicate_contracts
    payload = Master::Fix::UXRefinementCatalog.load
    duplicate = Marshal.load(Marshal.dump(payload))
    duplicate.fetch("refinements").last["id"] = duplicate.fetch("refinements").first.fetch("id")
    assert_raises(ArgumentError) { Master::Fix::UXRefinementCatalog.validate!(duplicate) }
    assert_raises(ArgumentError) { Master::Fix::UXRefinementCatalog.validate!({ "refinements" => [] }) }
  end

  def test_verified_state_requires_pass_evidence_for_every_declared_proof_type
    payload = Marshal.load(Marshal.dump(Master::Fix::UXRefinementCatalog.load))
    row = payload.fetch("refinements").first
    row["state"] = "verified"
    row["evidence"] = row.fetch("proof").map do |proof_type|
      {
        "proof_type" => proof_type,
        "result" => "PASS",
        "location" => "MASTER/test/test_ux_refinement_catalog.rb",
        "sha256" => "a" * 64,
        "commit" => "b" * 40
      }
    end

    assert Master::Fix::UXRefinementCatalog.validate!(payload)

    incomplete = Marshal.load(Marshal.dump(payload))
    incomplete.fetch("refinements").first.fetch("evidence").pop
    assert_raises(ArgumentError) { Master::Fix::UXRefinementCatalog.validate!(incomplete) }

    no_digest = Marshal.load(Marshal.dump(payload))
    no_digest.fetch("refinements").first.fetch("evidence").first.delete("sha256")
    assert_raises(ArgumentError) { Master::Fix::UXRefinementCatalog.validate!(no_digest) }

    unsafe_path = Marshal.load(Marshal.dump(payload))
    unsafe_path.fetch("refinements").first.fetch("evidence").first["location"] = "../external.log"
    assert_raises(ArgumentError) { Master::Fix::UXRefinementCatalog.validate!(unsafe_path) }
  end

  def test_catalog_rejects_gaps_in_the_id_sequence_and_false_completion_states
    payload = Master::Fix::UXRefinementCatalog.load
    missing = Marshal.load(Marshal.dump(payload))
    missing.fetch("refinements")[40]["id"] = "UX091"
    assert_raises(ArgumentError) { Master::Fix::UXRefinementCatalog.validate!(missing) }
    completed = Marshal.load(Marshal.dump(payload))
    completed.fetch("refinements").first["state"] = "complete"
    assert_raises(ArgumentError) { Master::Fix::UXRefinementCatalog.validate!(completed) }
  end

  def test_prompt_context_is_scoped_to_target_and_never_claims_passing
    root = "/work/pub4"
    master = Master::Fix::UXRefinementCatalog.prompt_context(target: "#{root}/MASTER", root: root)
    rails = Master::Fix::UXRefinementCatalog.prompt_context(target: "#{root}/RAILS", root: root)
    openbsd = Master::Fix::UXRefinementCatalog.prompt_context(target: "#{root}/OPENBSD", root: root)
    all = Master::Fix::UXRefinementCatalog.prompt_context(target: root, root: root)
    assert_includes master, "UX001"
    assert_includes rails, "UX063"
    assert_includes openbsd, "UX031"
    assert_equal 90, all.lines.count { |line| line.match?(/\AUX\d{3} \[/) }
    refute_match(/all 90 (?:tests|behaviors) pass/i, all)
  end
end
