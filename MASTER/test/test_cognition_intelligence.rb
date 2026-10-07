# frozen_string_literal: true

require_relative "test_helper"

class TestCognitionIntelligence < Minitest::Test
  def test_route_uses_existing_evidence_router
    route = Master::Cognition::Intelligence.route("what is latest with the repo")
    assert_equal :web_current, route[:mode]
    assert_equal :search_current, route[:action]
    assert_equal true, route[:web_required]
  end

  def test_claim_frame_requires_observation_falsifier_and_measurement
    frame = Master::Cognition::Intelligence.claim_frame(
      claim: "the refactor is safer",
      observation: "the focused tests pass",
      inference: "the changed path is narrower",
      falsifier: "an unchanged contract regresses",
      measurement: "targeted test suite",
      source: "test:test_refactor",
    )
    assert frame[:ready_to_verify]
    assert_equal :uncertain, frame[:status]
  end

  def test_causal_trace_identifies_broken_handoff
    trace = Master::Cognition::Intelligence.causal_trace([
      { cause: "scan", effect: "finding", evidence: "scan log" },
      { cause: "repair", effect: "clean tree", evidence: "test pass" },
    ])
    refute trace[:complete]
    assert_equal({ from: "finding", to: "repair" }, trace[:gaps].first)
  end

  def test_compression_keeps_provenance
    rows = Master::Cognition::Intelligence.compress([
      { label: "same law", source: "laws.yml" },
      { label: "same law", source: "test_law.rb" },
      { label: "other", source: "other.rb" },
    ])
    assert_equal "same law", rows.first[:label]
    assert_equal %w[laws.yml test_law.rb], rows.first[:sources]
    assert_equal 2, rows.first[:count]
  end

  def test_falsification_questions_are_counterexamples_not_answers
    questions = Master::Cognition::Intelligence.falsification_questions("the patch is harmless")
    assert_equal 5, questions.size
    assert_includes questions.first, "false"
    assert_includes questions.last, "obsolete"
  end
end
