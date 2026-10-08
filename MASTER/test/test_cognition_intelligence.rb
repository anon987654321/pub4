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

  def test_attention_budget_preserves_one_high_uncertainty_candidate
    high = { rule: "ROOT", severity: :warning, consumers: 8, confidence: 0.9 }
    uncertain = { rule: "UNKNOWN", consumers: 0, confidence: 0.1, status: :uncertain }
    noisy = { rule: "NOISE", severity: :critical, consumers: 0, confidence: 0.9 }

    budget = Master::Cognition::Intelligence.attention_budget([high, uncertain, noisy], slots: 1)

    assert_equal 3, budget[:candidates]
    assert_includes budget[:selected], high
    assert_includes budget[:selected], uncertain
    assert_equal 1, budget[:deferred].size
    assert_equal uncertain, budget[:preserved_uncertainty]
  end

  def test_leverage_prefers_causal_reach_over_severity_noise
    rows = Master::Cognition::Intelligence.rank_by_leverage([
      { rule: "NOISY", severity: :critical, blast_radius: { files_touched: 1, consumers: 0 } },
      { rule: "ROOT", severity: :warning, blast_radius: { files_touched: 2, consumers: 8, boundaries: 2, rules: 3 } },
    ])

    assert_equal "ROOT", rows.first[:rule]
    assert_operator Master::Cognition::Intelligence.leverage_score(rows.first), :>, 30
  end

  def test_conceptual_equivalence_ignores_names_and_order
    left = {
      purpose: "Preserve the current contract",
      inputs: ["source", "tests"],
      outputs: ["verified result"],
      side_effects: ["write"],
      invariants: ["public api"],
    }
    right = {
      invariants: ["public API"],
      side_effects: ["write"],
      outputs: ["verified result"],
      inputs: ["tests", "source"],
      purpose: "  preserve the current contract ",
      name: "another_name",
    }

    assert Master::Cognition::Intelligence.conceptually_equivalent?(left, right)
  end

  def test_decision_frame_keeps_uncertainty_alternatives_and_causality
    frame = Master::Cognition::Intelligence.decision_frame(
      observation: "one test changed",
      hypothesis: "the smaller change is safer",
      falsifier: "another caller regresses",
      measurement: "targeted tests",
      source: "test:example",
      selected: "keep the smaller change",
      alternatives: ["rewrite the module", "defer the change"],
      cause: "observed diff",
      effect: "candidate repair",
    )

    assert_equal :uncertain, frame[:status]
    assert_equal ["rewrite the module", "defer the change"], frame["alternatives"]
    assert_equal "observed diff", frame["causal"]["cause"]
  end

  def test_uncertain_reversible_work_gets_an_exploratory_posture
    item = { confidence: 0.7, status: :uncertain, reversibility: :reversible }
    assert_equal :explore, Master::Cognition::Intelligence.posture_for(item)
  end

  def test_decision_frame_teaches_from_local_observation_to_consequence
    frame = Master::Cognition::Intelligence.decision_frame(
      observation: "the reader changed",
      hypothesis: "the caller contract may drift",
      falsifier: "existing contract suite remains green",
      measurement: "caller contract suite",
      source: "MASTER/lib/core.rb",
      selected: "verify callers first",
    )

    assert_equal "the reader changed", frame["teaching"][:local]
    assert_equal "MASTER/lib/core.rb", frame["teaching"][:boundary]
    assert_equal "verify callers first", frame["teaching"][:next_step]
  end

  def test_fertility_does_not_call_inactivity_dead_without_enough_evidence
    result = Master::Cognition::Intelligence.fertility(consumers: 0, unused_days: 200, confidence: 0.5)

    assert_equal :investigate, result[:posture]
    assert_includes result[:dead_evidence], :long_unused
  end

  def test_counterfactual_frame_names_a_separating_measurement
    frame = Master::Cognition::Intelligence.counterfactual_frame(
      hypothesis: "the smaller change is safer",
      alternative: "the wrapper removal is safer",
      boundary: "public CLI",
      measurement: "existing command contract suite",
      expected_difference: "one path keeps the alias, the other removes it",
    )

    assert frame[:ready]
    assert_equal "public CLI", frame[:boundary]
  end

  def test_synthesis_keeps_dissent_instead_of_majority_vote
    result = Master::Cognition::Intelligence.synthesize_judgments([
      { persona: "A", claim: "keep wrapper", confidence: 0.9, falsifier: "caller breaks" },
      { persona: "B", claim: "remove wrapper", confidence: 0.85, falsifier: "caller break" },
      { persona: "C", claim: "keep wrapper", confidence: 0.6, falsifier: "caller breaks" },
    ])

    assert result[:disagreement]
    assert result[:requires_measurement]
    assert_nil result[:leading]
    assert_equal 2, result[:positions].size
  end

  def test_fertility_preserves_promising_unfinished_work
    result = Master::Cognition::Intelligence.fertility(
      consumers: 2,
      operator_owned: true,
      novelty: 0.8,
      unused_days: 20,
    )

    assert_equal :fertile, result[:posture]
    assert_includes result[:value_evidence], :consumers
  end

  def test_falsification_questions_are_counterexamples_not_answers
    questions = Master::Cognition::Intelligence.falsification_questions("the patch is harmless")
    assert_equal 5, questions.size
    assert_includes questions.first, "false"
    assert_includes questions.last, "obsolete"
  end
end
