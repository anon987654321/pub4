# frozen_string_literal: true

require_relative "test_helper"
require_relative "../lib/execution/contract"
require_relative "../lib/proof"
require_relative "../lib/trace/effect_observer"
require_relative "../lib/fix/outcome_policy"
require_relative "../checks/support/check_ledger"

class TestExecutionContract < Minitest::Test
  Contract = Master::Execution::Contract

  class RecordingBus
    attr_reader :events

    def initialize = @events = []

    def publish_required(name, payload = {})
      @events << [name, payload]
    end
  end

  def test_fix_uses_the_canonical_terminal_state_vocabulary
    assert_same Contract::TERMINAL_STATES, Master::Fix::OutcomePolicy::TERMINAL_STATES
    assert_equal :cancelled, Contract.normalize_terminal_state("CANCELLED")
    assert_equal :unknown_outcome, Contract.normalize_terminal_state(:unknown_outcome)
    assert_equal :recovery_failed, Contract.normalize_terminal_state(:recovery_failed)
    assert_nil Contract.normalize_terminal_state("not-a-terminal-state")
    assert_nil Contract.normalize_terminal_state(nil)
  end

  def test_effect_envelope_correlates_a_run_without_exposing_arguments_or_scope
    effect = Master::Core::Effect.write("private-name.txt", "private contents")
    envelope = Contract::EffectEnvelope.build(
      effect:, turn: 2, effect_id: "effect-1", run_id: "run-1", attempt_id: "attempt-1",
      mission_id: "mission-1", scope: "private-workspace/private-name.txt"
    )
    payload = envelope.to_h

    assert_equal 1, payload[:schema_version]
    assert_equal "effect-1", payload[:effect_id]
    assert_equal "run-1", payload[:run_id]
    assert_equal "attempt-1", payload[:attempt_id]
    assert_equal "mission-1", payload[:mission_id]
    assert_equal Digest::SHA256.hexdigest("private-workspace/private-name.txt"), payload[:scope_digest]
    refute_includes payload.inspect, "private-name.txt"
    refute_includes payload.inspect, "private contents"
    refute_includes payload.inspect, "private-workspace"
  end

  def test_envelope_rejects_invalid_identity_operation_and_turn
    effect = Master::Core::Effect.read("README.md")

    assert_raises(ArgumentError) do
      Contract::EffectEnvelope.build(effect:, turn: 0, effect_id: "bad/id")
    end
    assert_raises(ArgumentError) do
      Contract::EffectEnvelope.build(effect:, turn: -1, effect_id: "effect-1")
    end
    assert_raises(ArgumentError) do
      Contract::EffectEnvelope.build(effect:, turn: 0, effect_id: "effect-1", operation: :unknown)
    end
  end

  def test_rollback_envelope_keeps_parent_effect_and_checkpoint_identity
    effect = Master::Core::Effect.write("private.txt", "private")
    envelope = Contract::EffectEnvelope.build(
      effect:, turn: 4, effect_id: "rollback-1", operation: :rollback,
      parent_effect_id: "effect-1", checkpoint_id: "checkpoint-1", run_id: "run-1"
    )

    assert_equal :rollback, envelope.operation
    assert_equal "effect-1", envelope.parent_effect_id
    assert_equal "checkpoint-1", envelope.checkpoint_id
    refute_includes envelope.to_h.inspect, "private.txt"
    refute_includes envelope.to_h.inspect, "private"
  end

  def test_evidence_reference_is_typed_and_contains_no_content
    reference = Contract::EvidenceReference.new(
      id: "proof-1", kind: "test_output", status: :verified,
      verifier: "focused-test", digest: "a" * 64
    )

    assert_equal :verified, reference.to_h[:status]
    refute reference.to_h.key?(:content)
    assert_raises(ArgumentError) do
      Contract::EvidenceReference.new(
        id: "private/path", kind: "test_output", status: :verified, verifier: "focused-test"
      )
    end
    assert_raises(ArgumentError) do
      Contract::EvidenceReference.new(
        id: "proof-2", kind: "test_output", status: :pass, verifier: "focused-test"
      )
    end
  end

  def test_effect_observer_adds_run_identity_and_only_typed_evidence_references
    bus = RecordingBus.new
    observer = Master::Trace::EffectObserver.new(
      bus:, run_id: "run-77", attempt_id: "attempt-77", mission_id: "mission-77"
    )
    effect = Master::Core::Effect.write("hidden.txt", "sensitive data")
    proof = Contract::EvidenceReference.new(
      id: "proof-77", kind: "test_output", status: :verified, verifier: "focused-test"
    )

    observer.call(
      stage: :before, turn: 1, effect:, effect_id: "effect-77",
      scope: "private/hidden.txt", evidence_refs: [proof]
    )
    observer.call(
      stage: :after, turn: 1, effect:, effect_id: "effect-77",
      scope: "private/hidden.txt", evidence_refs: [proof],
      observation: Master::Core::Observation.ok("written"), elapsed_ms: 3
    )

    before, after = bus.events.map(&:last)
    assert_equal "run-77", before[:run_id]
    assert_equal before[:run_id], after[:run_id]
    assert_equal "attempt-77", before[:attempt_id]
    assert_equal before[:attempt_id], after[:attempt_id]
    assert_equal "mission-77", before[:mission_id]
    assert_equal [{ id: "proof-77", kind: "test_output", status: :verified, verifier: "focused-test" }],
                 before[:evidence_refs]
    refute_includes bus.events.inspect, "hidden.txt"
    refute_includes bus.events.inspect, "sensitive data"
    refute_includes bus.events.inspect, "private/"
  end

  def test_effect_observer_rejects_untyped_evidence_references
    observer = Master::Trace::EffectObserver.new(bus: RecordingBus.new)
    error = assert_raises(ArgumentError) do
      observer.call(
        stage: :before, turn: 0, effect: Master::Core::Effect.read("README.md"),
        effect_id: "effect-1", evidence_refs: [{ id: "proof-1", content: "private" }]
      )
    end

    assert_match(/typed EvidenceReference/, error.message)
  end

  class FakeCheckResult
    attr_reader :outcome, :checks_ran, :failures, :warnings, :unchecked

    def initialize(outcome:, checks_ran:, failures: [], warnings: [], unchecked: [], conclusive: true)
      @outcome = outcome
      @checks_ran = checks_ran
      @failures = failures
      @warnings = warnings
      @unchecked = unchecked
      @conclusive = conclusive
    end

    def conclusive? = @conclusive
  end

  def test_check_result_adapter_preserves_partial_and_inconclusive_semantics
    partial = Contract::VerificationResult.from_check_result(
      FakeCheckResult.new(
        outcome: :passed, checks_ran: 12, failures: [], warnings: ["one warning"],
        unchecked: ["browser unavailable"], conclusive: false
      ),
      id: "check-partial", subject: "web-contract", verifier: "check-runner",
      scope: "RAILS/master"
    )
    inconclusive = Contract::VerificationResult.from_check_result(
      FakeCheckResult.new(outcome: :inconclusive, checks_ran: 0, unchecked: ["app not listening"]),
      id: "check-inconclusive", subject: "live-layout", verifier: "check-runner"
    )
    failed = Contract::VerificationResult.from_check_result(
      FakeCheckResult.new(outcome: :failed, checks_ran: 4, failures: ["fixture failure"]),
      id: "check-failed", subject: "unit-tests", verifier: "minitest"
    )
    errored = Contract::VerificationResult.from_check_result(
      FakeCheckResult.new(outcome: :errored, checks_ran: 0),
      id: "check-errored", subject: "unit-tests", verifier: "minitest"
    )

    assert_equal :partial, partial.status
    assert_equal 12, partial.checked_count
    assert_equal 1, partial.warning_count
    assert_equal 1, partial.unchecked_count
    assert_equal Digest::SHA256.hexdigest("RAILS/master"), partial.scope_digest
    refute partial.conclusive?

    assert_equal :inconclusive, inconclusive.status
    refute inconclusive.complete
    assert_equal :fail, failed.status
    assert_equal 1, failed.failure_count
    assert_predicate failed, :conclusive?
    assert_equal :error, errored.status
    refute_predicate errored, :conclusive?
  end

  def test_check_ledger_stores_normalized_receipt_alongside_legacy_counts
    Dir.mktmpdir do |dir|
      ledger = Deploy::CheckLedger.new(path: File.join(dir, "checks.jsonl"))
      result = FakeCheckResult.new(outcome: :passed, checks_ran: 4, failures: [], warnings: ["warning"])
      receipt = Contract::VerificationResult.from_check_result(
        result, id: "run-1:check-1", subject: "example-check", verifier: "pub4-check-runner", scope: "MASTER/checks"
      )

      ledger.record(check: "example-check", outcome: result.outcome, run_id: "run-1", verification: receipt.to_h)
      entry = ledger.entries.fetch(0)

      assert_equal "passed", entry.fetch("outcome")
      assert_equal "pass", entry.dig("verification", "status")
      assert_equal "pub4-check-runner", entry.dig("verification", "verifier")
      assert_equal Digest::SHA256.hexdigest("MASTER/checks"), entry.dig("verification", "scope_digest")
      refute entry.dig("verification").key?("failure_details")
    end
  end

  def test_check_result_adapter_preserves_infrastructure_outcomes
    {
      partial: :partial,
      blocked: :blocked,
      timeout: :timeout,
      timed_out: :timeout,
      unavailable: :unavailable,
      skipped: :not_applicable
    }.each do |source, expected|
      result = Contract::VerificationResult.from_check_result(
        FakeCheckResult.new(outcome: source, checks_ran: 0),
        id: "check-#{source}", subject: "integration-check", verifier: "adapter"
      )
      assert_equal expected, result.status
      refute_predicate result, :conclusive?
    end
  end

  def test_proof_adapter_preserves_open_claims_as_inconclusive
    proven = Master::Proof.build(
      claim: "test suite passed", law: "ROBUSTNESS", subject: "MASTER",
      evidence: "local command receipt", source: :deterministic, status: :proven
    )
    open = Master::Proof.build(
      claim: "browser output not available", law: "CAPABILITY_STATUS_MUST_BE_TRUTHFUL",
      subject: "RAILS", source: :deterministic, status: :open
    )

    passed = proven.to_verification(id: "proof-pass", verifier: "proof-adapter", scope: "MASTER")
    inconclusive = open.to_verification(id: "proof-open", verifier: "proof-adapter")

    assert_equal :pass, passed.status
    assert_equal Digest::SHA256.hexdigest("MASTER"), passed.scope_digest
    assert_equal :inconclusive, inconclusive.status
    refute inconclusive.complete
    refute_includes inconclusive.to_h.inspect, "browser output not available"
  end
  def test_skill_contract_is_versioned_and_requires_fixtures_for_promotion
    candidate = Contract::SkillContract.from_declaration(
      name: "release-skill", revision: "b" * 64, source: :registry,
      declaration: {
        "schema_version" => 1,
        "version" => "1.2.0",
        "status" => "candidate",
        "risk" => "medium",
        "required_capabilities" => ["read", "network"],
        "laws" => ["ROBUSTNESS", "CAPABILITY_STATUS_MUST_BE_TRUTHFUL"],
        "fixtures" => ["MASTER/test/test_skills.rb"],
        "provenance" => "reviewed-in-source"
      }
    )
    legacy = Contract::SkillContract.from_declaration(
      name: "legacy", revision: "c" * 64, source: :registry
    )
    incomplete = Contract::SkillContract.from_declaration(
      name: "incomplete", revision: "d" * 64, source: :registry,
      declaration: { "version" => "1.0.0", "status" => "candidate" }
    )

    assert_predicate candidate, :promotable?
    assert_equal :candidate, candidate.status
    refute_predicate candidate, :permitted_for_trigger?,
                     "a declared candidate is not active until it is approved"
    assert_equal :unreviewed, legacy.status
    assert_predicate legacy, :permitted_for_trigger?,
                     "legacy skills keep the existing behavior while migration proceeds"
    refute_predicate incomplete, :promotable?
  end

  def test_invalid_skill_contract_never_promotes
    contract = Contract::SkillContract.from_declaration(
      name: "bad-skill", revision: "e" * 64, source: :registry,
      declaration: {
        "version" => "not-semver",
        "status" => "self-approved",
        "required_capabilities" => ["../admin"],
        "mystery" => true
      }
    )

    assert_equal :invalid, contract.status
    refute_predicate contract, :permitted_for_trigger?
    refute_predicate contract, :promotable?
    assert_includes contract.errors, "invalid_version"
    assert_includes contract.errors, "unknown_fields"
  end

end
