# frozen_string_literal: true

require_relative "test_helper"
require_relative "../lib/fix/task_contract"

class TestTaskContract < Minitest::Test
  CONTRACT = Master::Fix::TaskContract

  def test_content_only_adds_all_mandatory_preservation_and_proof
    contract = CONTRACT.build(
      intent: "content_only",
      scope: ["FETAT.html"],
      preserve: ["visual_identity"],
      proof: ["focused_tests"],
    )

    assert_includes contract.preserve, "structure"
    assert_includes contract.preserve, "operator_owned_values"
    assert_includes contract.proof, "baseline_hashes"
    assert_includes contract.proof, "law_assessment"
  end

  def test_rejects_parent_traversal_and_absolute_paths
    ["../outside", "/etc/passwd", "RAILS/../../outside"].each do |path|
      assert_raises(CONTRACT::Invalid) do
        CONTRACT.build(intent: "content_only", scope: [path], preserve: [], proof: [])
      end
    end
  end

  def test_rejects_unknown_intent_and_proof_type
    base = { scope: ["MASTER/file.rb"], preserve: [], proof: [] }
    assert_raises(CONTRACT::Invalid) { CONTRACT.build(base.merge(intent: "make_it_pretty")) }
    assert_raises(CONTRACT::Invalid) do
      CONTRACT.build(base.merge(intent: "content_only", proof: ["trust_me"]))
    end
  end

  def test_contract_round_trips_and_covers_a_scoped_file
    contract = CONTRACT.build(
      intent: "functional_change",
      scope: ["RAILS/brgen/**"],
      preserve: [],
      proof: ["focused_tests", "rendered_evidence"],
    )

    assert_equal 1, contract.to_h.fetch("schema")
    assert_equal "functional_change", contract.to_h.fetch("intent")
    assert CONTRACT.covers?("RAILS/brgen/app/models/item.rb", scope: contract.scope)
    refute CONTRACT.covers?("RAILS/amber/app/models/item.rb", scope: contract.scope)
    assert_equal ["baseline_hashes", "law_assessment", "path_scoped_diff"],
                 contract.proof.grep(/baseline_hashes|law_assessment|path_scoped_diff/)
  end
end
