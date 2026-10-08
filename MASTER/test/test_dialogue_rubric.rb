# frozen_string_literal: true

require_relative "test_helper"
require "master"
require_relative "../lib/voice/dialogue_rubric"

class TestDialogueRubric < Minitest::Test
  Rubric = Master::Voice::DialogueRubric

  def test_the_rubric_is_a_single_validated_source
    data = Rubric.data(root: Master::ROOT)

    assert Rubric.valid?(root: Master::ROOT)
    assert_equal 6, data.fetch("dimensions").size
    assert_equal 3, data.fetch("sycophancy_fixtures").size
    assert_equal 3, data.fetch("bench").fetch("sycophancy_fixture_count")
  end

  def test_prompt_block_carries_conversation_law
    block = Rubric.prompt_block(root: Master::ROOT)

    assert_includes block, "<master_dialogue_rubric>"
    assert_includes block, "Calibrate certainty to evidence"
    assert_includes block, "Disagree when a claim is wrong"
  end

  def test_forbidden_openers_are_rejected
    assert_equal ["no_ai_isms: Great question"], Rubric.evaluate("Great question! The answer is 42.", root: Master::ROOT)
    assert_empty Rubric.evaluate("The answer is 42.", root: Master::ROOT)
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
