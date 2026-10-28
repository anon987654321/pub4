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
    Dir.mktmpdir("ux-evidence-receipts") do |root|
      out, status = Master::Io::Exec.capture2e("git", "-C", root, "init", "--quiet")
      assert status.success?, out
      evidence_path = File.join(root, "evidence.txt")
      evidence_text = "actual test output: PASS\n"
      File.write(evidence_path, evidence_text)
      _add_out, add_status = Master::Io::Exec.capture2e("git", "-C", root, "add", "evidence.txt")
      assert add_status.success?
      commit_out, commit_status = Master::Io::Exec.capture2e(
        "git", "-C", root, "-c", "user.name=UX Test", "-c", "user.email=ux-test@example.invalid",
        "commit", "--quiet", "-m", "fixture evidence"
      )
      assert commit_status.success?, commit_out
      commit, commit_status = Master::Io::Exec.capture2("git", "-C", root, "rev-parse", "HEAD")
      assert commit_status.success?

      row["evidence"] = row.fetch("proof").map do |proof_type|
        {
          "proof_type" => proof_type,
          "result" => "PASS",
          "location" => "evidence.txt",
          "sha256" => Digest::SHA256.hexdigest(evidence_text),
          "commit" => commit.strip,
        }
      end

      assert Master::Fix::UXRefinementCatalog.validate!(payload, root:)

      incomplete = Marshal.load(Marshal.dump(payload))
      incomplete.fetch("refinements").first.fetch("evidence").pop
      assert_raises(ArgumentError) { Master::Fix::UXRefinementCatalog.validate!(incomplete, root:) }

      no_digest = Marshal.load(Marshal.dump(payload))
      no_digest.fetch("refinements").first.fetch("evidence").first.delete("sha256")
      assert_raises(ArgumentError) { Master::Fix::UXRefinementCatalog.validate!(no_digest, root:) }

      unsafe_path = Marshal.load(Marshal.dump(payload))
      unsafe_path.fetch("refinements").first.fetch("evidence").first["location"] = "../external.log"
      assert_raises(ArgumentError) { Master::Fix::UXRefinementCatalog.validate!(unsafe_path, root:) }

      tampered = Marshal.load(Marshal.dump(payload))
      File.write(evidence_path, "edited after PASS\n")
      assert_raises(ArgumentError) { Master::Fix::UXRefinementCatalog.validate!(tampered, root:) }
    end
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
    master = Master::Fix::UXRefinementCatalog.prompt_context(target: "#{root}/MASTER", root:)
    rails = Master::Fix::UXRefinementCatalog.prompt_context(target: "#{root}/RAILS", root:)
    openbsd = Master::Fix::UXRefinementCatalog.prompt_context(target: "#{root}/OPENBSD", root:)
    all = Master::Fix::UXRefinementCatalog.prompt_context(target: root, root:)
    assert_includes master, "UX001"
    assert_includes rails, "UX063"
    assert_includes openbsd, "UX031"
    assert_equal 90, all.lines.count { |line| line.match?(/\AUX\d{3} \[/) }
    refute_match(/all 90 (?:tests|behaviors) pass/i, all)
  end
end
