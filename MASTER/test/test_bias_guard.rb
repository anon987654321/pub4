# frozen_string_literal: true

require_relative "test_helper"

class TestBiasGuard < Minitest::Test
  Proposal = Struct.new(:action, :reason, :weight, :confidence, :impact, :kind, keyword_init: true) do
    def [](key)
      key == :rank ? confidence.to_f * impact.to_f : public_send(key)
    end

    def to_h
      {
        action:,
        reason:,
        weight:,
        confidence:,
        impact:,
        kind:,
        rank: self[:rank],
      }
    end
  end

  def test_annotates_confirmation_bias_with_countermeasure
    guard = Master::Ground::BiasGuard.new
    proposal = Proposal.new(
      action: "/fix",
      reason: "scanner result has violation",
      weight: 0.8,
      confidence: 0.9,
      impact: 0.9,
      kind: :violation,
    )

    annotated = guard.annotate(proposal)

    assert_includes annotated[:reason], "confirmation_bias"
    assert_operator annotated[:confidence], :<, proposal.confidence
  end

  def test_detects_the_four_decision_biases
    guard = Master::Ground::BiasGuard.new
    hits = {
      "optimism_bias" => Proposal.new(action: "/through", reason: "quick trivial simple fix", weight: 0.5, confidence: 0.8, impact: 0.5, kind: :task),
      "dunning_kruger_bias" => Proposal.new(action: "/through", reason: "obviously clearly straightforward", weight: 0.5, confidence: 0.8, impact: 0.5, kind: :task),
      "bandwagon_bias" => Proposal.new(action: "/through", reason: "everyone uses this best practice", weight: 0.5, confidence: 0.8, impact: 0.5, kind: :task),
      "framing_bias" => Proposal.new(action: "/through", reason: "the real problem is naming", weight: 0.5, confidence: 0.8, impact: 0.5, kind: :task),
    }
    hits.each do |name, proposal|
      assert_includes guard.detect(proposal), name
      assert_includes guard.annotate(proposal)[:reason], name
    end
  end

  def test_priority_score_combines_severity_frequency_and_age
    guard = Master::Ground::BiasGuard.new
    fresh = guard.priority_score(severity: :warning, frequency: 3, age_days: 0)
    old = guard.priority_score(severity: :error, frequency: 2, age_days: 60)

    assert_operator old, :>, fresh
  end
end
