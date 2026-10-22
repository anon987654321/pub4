# frozen_string_literal: true

require_relative "test_helper"

class TestProofAdapters < Minitest::Test
  def test_finding_maps_to_deterministic_proof
    finding = Master::Review::Scan::Finding.build(
      law: "STYLE",
      message: "style issue",
      line: 12,
      severity: :warning,
    )

    proof = finding.to_proof(subject: "lib/example.rb")

    assert_equal "style issue", proof.claim
    assert_equal "STYLE", proof.law
    assert_equal "lib/example.rb", proof.subject
    assert_equal :deterministic, proof.source
    assert_equal :open, proof.status
    assert proof.open?
  end

  def test_verdict_maps_to_council_proof
    verdict = Master::Review::Verdict.new.call(
      deterministic: { syntax: true },
      rubric_score: 0.9,
    )

    proof = verdict.to_proof(claim: "review passed", law: "REVIEW")

    assert_equal "review passed", proof.claim
    assert_equal "REVIEW", proof.law
    assert_equal :council, proof.source
    assert_equal :proven, proof.status
    assert proof.proven?
  end

  def test_proof_freezes_nested_evidence
    proof = Master::Proof.build(claim: "x", evidence: { paths: ["a.rb"] })

    assert proof.metadata.frozen?
    assert proof.evidence.frozen?
    assert proof.evidence["paths"].frozen?
  end

  def test_proof_rejects_unknown_sources
    assert_raises(ArgumentError) do
      Master::Proof.build(claim: "x", source: :human)
    end
  end

  def test_core_proof_remains_distinct
    refute_equal Master::Proof, Master::Core::Proof
  end
end
