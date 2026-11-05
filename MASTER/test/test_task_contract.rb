# frozen_string_literal: true

require_relative "test_helper"
require "tmpdir"
require_relative "../lib/fix/task_contract"
require_relative "../lib/fix/artifact_preservation"
require_relative "../lib/fix/transaction"

class TestTaskContract < Minitest::Test
  CONTRACT = Master::Fix::TaskContract

  def test_current_contract_is_nested_and_restored_after_exceptions
    first = CONTRACT.build(intent: "content_only", scope: ["one.txt"], preserve: [], proof: [])
    second = CONTRACT.build(intent: "content_only", scope: ["two.txt"], preserve: [], proof: [])

    assert_nil CONTRACT.current
    assert_raises(RuntimeError) do
      CONTRACT.with_current(first) do
        assert_equal first, CONTRACT.current
        CONTRACT.with_current(second) { assert_equal second, CONTRACT.current }
        assert_equal first, CONTRACT.current
        raise "leave the contract scope"
      end
    end
    assert_nil CONTRACT.current
  end

  def test_preservation_receipts_are_plan_bound_and_nested_scopes_are_restored
    first = CONTRACT.build(intent: "content_only", scope: ["page.html"], preserve: [], proof: [])
    second = CONTRACT.build(intent: "functional_change", scope: ["worker.rb"], preserve: [], proof: [])
    result = Master::Fix::ArtifactPreservation::Result.new("PASS", ["html_markup"], nil)

    CONTRACT.with_current(first) do
      CONTRACT.attach_plan!("plan-one")
      row = CONTRACT.record_preservation!(
        path: File.join(Master::REPO_ROOT, "page.html"),
        format: "html",
        before: "<p>before</p>",
        after: "<p>after</p>",
        result:,
      )
      assert_equal "plan-one", row.fetch("plan_digest")
      assert_match(/\A[0-9a-f]{64}\z/, row.fetch("before_sha256"))
      assert_equal "INCONCLUSIVE", CONTRACT.preservation_evidence.fetch("status")

      CONTRACT.with_current(second) do
        assert_equal "not_measured", CONTRACT.preservation_evidence.fetch("status")
        CONTRACT.attach_plan!("plan-two")
        CONTRACT.record_preservation!(
          path: File.join(Master::REPO_ROOT, "worker.rb"),
          format: "rb",
          before: "x = 1",
          after: "x = 2",
          result: Master::Fix::ArtifactPreservation::Result.new("INCONCLUSIVE", [], "no Ruby source verifier"),
        )
        assert_equal "plan-two", CONTRACT.preservation_evidence.fetch("plan_digest")
      end

      evidence = CONTRACT.preservation_evidence
      assert_equal "plan-one", evidence.fetch("plan_digest")
      assert_equal ["page.html"], evidence.fetch("results").map { |entry| entry.fetch("path") }
    end

    assert_equal "not_measured", CONTRACT.preservation_evidence.fetch("status")
  end

  def test_transaction_rejects_out_of_scope_paths_before_snapshotting
    Dir.mktmpdir("task-contract-transaction") do |root|
      contract = CONTRACT.build(intent: "functional_change", scope: ["allowed.txt"], preserve: [], proof: [])

      CONTRACT.with_current(contract) do
        transaction = Master::Fix::Transaction.new(root:, paths: ["allowed.txt"])
        assert_instance_of Master::Fix::Transaction, transaction
        assert_raises(CONTRACT::Invalid) do
          Master::Fix::Transaction.new(root:, paths: ["blocked.txt"])
        end
      end
    end
  end

  def test_transaction_rejects_out_of_scope_enlistment
    Dir.mktmpdir("task-contract-enlistment") do |root|
      contract = CONTRACT.build(intent: "functional_change", scope: ["allowed.txt"], preserve: [], proof: [])

      CONTRACT.with_current(contract) do
        transaction = Master::Fix::Transaction.new(root:, paths: ["allowed.txt"]).begin!
        result = transaction.enlist!(["blocked.txt"])
        refute result.ok?
        assert_equal :policy, result.category
        assert_match(/outside task-contract scope/, result.message)
        assert transaction.rollback!.ok?
      end
    end
  end

  def test_new_paths_are_exact_justified_and_inside_scope
    contract = CONTRACT.build(
      intent: "functional_change",
      scope: ["MASTER/lib/example.rb"],
      preserve: [],
      proof: [],
      new_paths: [{ path: "MASTER/lib/example.rb", reason: "A separately loaded protocol adapter." }],
    )

    assert_equal [{ "path" => "MASTER/lib/example.rb", "reason" => "A separately loaded protocol adapter." }],
                 contract.new_paths
    assert_equal contract.new_paths, contract.to_h.fetch("new_paths")
    assert_includes CONTRACT.agent_schema.fetch("optional_fields"), "new_paths"

    assert_raises(CONTRACT::Invalid) do
      CONTRACT.build(intent: "functional_change", scope: ["MASTER/lib/example.rb"],
                      preserve: [], proof: [], new_paths: [{ path: "MASTER/lib/example.rb" }])
    end
    assert_raises(CONTRACT::Invalid) do
      CONTRACT.build(intent: "functional_change", scope: ["MASTER/lib/**"],
                      preserve: [], proof: [], new_paths: [{ path: "MASTER/lib/example.rb", reason: "Scoped" },
                                                          { path: "MASTER/lib/example.rb", reason: "Duplicate" }])
    end
    assert_raises(CONTRACT::Invalid) do
      CONTRACT.build(intent: "functional_change", scope: ["MASTER/lib/**"],
                      preserve: [], proof: [], new_paths: [{ path: "MASTER/lib/new*.rb", reason: "Wildcard" }])
    end
    assert_raises(CONTRACT::Invalid) do
      CONTRACT.build(intent: "functional_change", scope: ["MASTER/lib/existing.rb"],
                      preserve: [], proof: [], new_paths: [{ path: "MASTER/lib/example.rb", reason: "Outside scope" }])
    end
  end

  def test_new_path_refusal_only_requires_declaration_for_missing_repo_paths
    Dir.mktmpdir("task-contract-new-path", Master::REPO_ROOT) do |root|
      relative = File.join(root.delete_prefix(Master::REPO_ROOT + File::SEPARATOR), "new.rb")
      path = File.join(root, "new.rb")
      undeclared = CONTRACT.build(intent: "functional_change", scope: [relative], preserve: [], proof: [])
      declared = CONTRACT.build(
        intent: "functional_change", scope: [relative], preserve: [], proof: [],
        new_paths: [{ path: relative, reason: "A distinct executable entrypoint." }],
      )

      assert_match(/new tracked path/, CONTRACT.new_path_refusal(path, contract: undeclared))
      assert_nil CONTRACT.new_path_refusal(path, contract: declared)
      File.write(path, "existing")
      assert_nil CONTRACT.new_path_refusal(path, contract: undeclared)
    end
  end

  def test_agent_prompt_explains_default_deny_new_path_policy
    prompt = CONTRACT.prompt

    assert_includes prompt, "A missing task contract is an empty new_paths declaration"
    assert_includes prompt, "must refuse every new tracked path"
  end

  def test_missing_contract_defaults_to_existing_paths_only
    Dir.mktmpdir("task-contract-default", Master::REPO_ROOT) do |root|
      path = File.join(root, "new.rb")

      CONTRACT.with_current(nil) do
        assert_match(/new tracked path/, CONTRACT.new_path_refusal(path))
        File.write(path, "existing")
        assert_nil CONTRACT.new_path_refusal(path)
      end
    end
  end

  def test_transaction_rejects_new_paths_without_an_active_contract
    Dir.mktmpdir("task-contract-default-transaction", Master::REPO_ROOT) do |root|
      relative = File.join(root.delete_prefix(Master::REPO_ROOT + File::SEPARATOR), "new.rb")

      CONTRACT.with_current(nil) do
        assert_raises(CONTRACT::Invalid) do
          Master::Fix::Transaction.new(root: Master::REPO_ROOT, paths: [relative])
        end
      end
    end
  end

  def test_transaction_rejects_undeclared_new_paths_and_accepts_declared_ones
    Dir.mktmpdir("task-contract-new-transaction", Master::REPO_ROOT) do |root|
      relative = File.join(root.delete_prefix(Master::REPO_ROOT + File::SEPARATOR), "created.rb")
      denied = CONTRACT.build(intent: "functional_change", scope: [relative], preserve: [], proof: [])
      allowed = CONTRACT.build(
        intent: "functional_change", scope: [relative], preserve: [], proof: [],
        new_paths: [{ path: relative, reason: "A distinct runtime adapter." }],
      )

      CONTRACT.with_current(denied) do
        assert_raises(CONTRACT::Invalid) { Master::Fix::Transaction.new(root:, paths: ["created.rb"]) }
      end

      CONTRACT.with_current(allowed) do
        transaction = Master::Fix::Transaction.new(root:, paths: ["created.rb"]).begin!
        assert transaction.rollback!.ok?
      end
    end
  end

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
    refute contract.to_h.key?("new_paths"), "empty declarations preserve the legacy contract digest shape"
    assert CONTRACT.covers?("RAILS/brgen/app/models/item.rb", scope: contract.scope)
    refute CONTRACT.covers?("RAILS/amber/app/models/item.rb", scope: contract.scope)
    assert_equal ["baseline_hashes", "law_assessment", "path_scoped_diff"],
                 contract.proof.grep(/baseline_hashes|law_assessment|path_scoped_diff/)
  end

  def test_documentation_review_is_an_accepted_proof_type
    contract = CONTRACT.build(
      intent: "functional_change",
      scope: ["MASTER/data/task_contract.yml"],
      preserve: [],
      proof: ["documentation_review"],
    )

    assert_includes contract.proof, "documentation_review"
  end
end
