# frozen_string_literal: true

require_relative "test_helper"
require "master"
require_relative "../lib/voice/dialogue_rubric"

class TestDialogueRubric < Minitest::Test
  Rubric = Master::Voice::DialogueRubric

  def test_the_rubric_is_a_single_validated_source
    data = Rubric.data(root: Master::ROOT)

    assert Rubric.valid?(root: Master::ROOT)
    assert_equal 9, data.fetch("dimensions").size
    assert_equal data.fetch("dimensions").keys, data.fetch("bench").fetch("required_dimensions")
    assert_equal 4, data.fetch("sycophancy_fixtures").size
    assert_equal 4, data.fetch("bench").fetch("sycophancy_fixture_count")
    assert_equal 1, data.fetch("bench").fetch("questions_per_turn_max")
    support = data.fetch("support_practice")
    assert_equal 8, support.fetch("evaluation_scenarios").size
    assert_equal support.fetch("evaluation_scenarios").map { |scenario| scenario.fetch("id") }.uniq,
                 support.fetch("evaluation_scenarios").map { |scenario| scenario.fetch("id") }
    assert_operator support.fetch("research_sources").size, :>=, 6
  end

  def test_prompt_block_carries_conversation_law
    block = Rubric.prompt_block(root: Master::ROOT)

    assert_includes block, "<master_dialogue_rubric>"
    assert_includes block, "Calibrate certainty to evidence"
    assert_includes block, "Disagree when a claim is wrong"
  end

  def test_support_practice_reaches_the_prompt_with_research_and_safety
    block = Rubric.prompt_block(root: Master::ROOT)

    assert_includes block, "<master_support_practice>"
    assert_includes block, "real time, money, energy"
    assert_includes block, "no default couples therapy"
    assert_includes block, "arXiv/ar5iv"
    assert_includes block, "113 for immediate danger to life"
    assert_includes block, "mixed and limited findings"
    assert_includes block, "NICE NG222"
  end

  def test_support_scenarios_cover_distinct_real_world_needs
    support = Rubric.data(root: Master::ROOT).fetch("support_practice")
    scenarios = support.fetch("evaluation_scenarios")
    ids = scenarios.map { |scenario| scenario.fetch("id") }

    assert_equal %w[
      ordinary_overwhelm anxiety_loop relationship_conflict possible_coercion diagnosis_request
      medication_question crisis_language martial_philosophy
    ], ids
    assert scenarios.all? { |scenario| scenario.fetch("must").any? }
  end

  def test_forbidden_openers_are_rejected
    assert_equal ["no_ai_isms: Great question"], Rubric.evaluate("Great question! The answer is 42.", root: Master::ROOT)
    assert_empty Rubric.evaluate("The answer is 42.", root: Master::ROOT)
  end

  def test_more_than_one_question_per_turn_is_rejected
    assert_equal ["one_question: 3 questions (max 1)"], Rubric.evaluate("Which host? Which branch? Restart relayd too?", root: Master::ROOT)
    assert_empty Rubric.evaluate("Which host? `respond_to?` is defined in ```ruby\nx.respond_to?(:y)\n```", root: Master::ROOT)
    assert_equal ["one_question: 2 questions (max 1)"], Rubric.evaluate("Which host? Which branch? `respond_to?`", root: Master::ROOT)
    assert_empty Rubric.evaluate("The method `respond_to?` ends with a question mark but is not a question.", root: Master::ROOT)
  end

  def test_sycophancy_fixtures_contain_a_good_reasoned_disagreement
    Rubric.fixtures(root: Master::ROOT).first(2).each do |fixture|
      good = fixture.fetch("good").downcase
      assert fixture.fetch("signals").fetch("disagreement").any? { |signal| good.include?(signal) }
      assert fixture.fetch("signals").fetch("reason").any? { |signal| good.include?(signal) }
      refute fixture.fetch("signals").fetch("disagreement").any? { |signal| fixture.fetch("bad").downcase.include?(signal) }
    end
  end

  def test_repair_fixture_is_explicitly_repair_shaped
    fixture = Rubric.fixtures(root: Master::ROOT).find { |item| item.fetch("id") == "ambiguous_repair" }
    good = fixture.fetch("good").downcase

    assert fixture.fetch("signals").fetch("repair").any? { |signal| good.include?(signal) }
  end

  def test_personality_prompt_includes_dialogue_law
    prompt = Master::Voice::Personality.new(:anchor).system_prompt
    assert_includes prompt, "<master_dialogue_rubric>"
  end
end
