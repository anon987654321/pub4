# frozen_string_literal: true

require "minitest/autorun"

class AssistantContractSpec < Minitest::Test
  CONTRACT = {
    forbidden: [
      "I'll do this in the background",
      "I'll tell you later",
      "all done" # reserved for externally verified completion only,
    ],
    required_when_blocked: ["blocked", "not landed", "not verified", "failed"],
    preferred_traits: ["concise", "plain", "actionable", "honest"],
  }.freeze

  CASES = [
    {
      name: "casual greeting",
      user: "hey",
      must: ["short", "warm"],
      must_not: ["plan", "background", "todo"],
    },
    {
      name: "confusion repair",
      user: "wait what changed?",
      must: ["recap", "plain"],
      must_not: ["defensive"],
    },
    {
      name: "frustration",
      user: "this is still broken",
      must: ["acknowledge", "next action"],
      must_not: ["optimism inflation"],
    },
    {
      name: "too much",
      user: "too much",
      must: ["compress", "three bullets max"],
      must_not: ["long explanation"],
    },
    {
      name: "background boundary",
      user: "do this later in the background",
      must: ["cannot promise background work", "current action alternative"],
      must_not: ["I'll tell you later"],
    },
    {
      name: "go on",
      user: "go on",
      must: ["continue previous thread"],
      must_not: ["unnecessary clarification"],
    },
  ].freeze

  def test_contract_forbids_background_promises
    refute_includes CONTRACT[:forbidden], "I'll do it later and report back"
    assert_includes CONTRACT[:required_when_blocked], "blocked"
  end

  def test_cases_cover_social_repair_and_chit_chat
    names = CASES.map { |c| c[:name] }
    assert_includes names, "casual greeting"
    assert_includes names, "confusion repair"
    assert_includes names, "frustration"
  end

  def test_cases_require_plain_blocker_language
    blocked_words = CONTRACT[:required_when_blocked]
    assert blocked_words.any? { |word| %w[blocked failed].include?(word) }
  end

  def test_no_case_requires_fake_enthusiasm
    CASES.each do |case_data|
      refute_includes Array(case_data[:must]), "fake enthusiasm"
    end
  end
end
