# frozen_string_literal: true

require_relative "test_helper"
require_relative "../lib/review/council/evidence"
require_relative "../lib/review/council/tribunal"

class TestCouncilTribunal < Minitest::Test
  Evidence = Master::Review::Council::Evidence

  def test_evidence_preserves_inconclusive
    evidence = Evidence.new(
      artifact: "face",
      domain: :visual,
      status: :inconclusive,
    )

    assert evidence.inconclusive?
    refute evidence.actionable?
  end

  def test_evidence_is_actionable_only_with_observation_and_anchor
    evidence = Evidence.new(
      artifact: "chat",
      domain: :ui,
      observations: ["button overlaps the footer"],
      anchors: ["button[data-action=send]"],
    )

    assert evidence.actionable?
  end

  def test_evidence_rejects_unknown_status
    assert_raises(ArgumentError) do
      Evidence.new(artifact: "x", domain: :general, status: :guess)
    end
  end

  def test_inconclusive_review_does_not_call_personas
    agent = Minitest::Mock.new
    tribunal = Master::Review::Council::Tribunal.new(agent:)

    result = tribunal.review(
      evidence: [
        Evidence.new(
          artifact: "audio",
          domain: :sound,
          status: :inconclusive,
        ),
      ],
      personas: [],
      context: "test",
    )

    assert result.ok?
    assert_equal :inconclusive, result.value![:status]
    assert_empty result.value![:feedback]
    agent.verify
  end

  def test_hash_evidence_is_normalized
    result = Master::Review::Council::Tribunal.new(agent: Object.new).send(
      :normalize,
      {
        artifact: "code",
        domain: "general",
        status: "observed",
        observations: ["x"],
        anchors: ["MASTER/lib/example.rb:1"],
      },
    )

    assert_equal :observed, result.first.status
    assert_equal :general, result.first.domain
  end
end
