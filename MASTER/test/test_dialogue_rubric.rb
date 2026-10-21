# frozen_string_literal: true

require_relative "test_helper"
require "master"
require_relative "../lib/voice/dialogue_rubric"
require_relative "../lib/review/agent/prompt_builder"

class SupportPromptHost
  include Master::Review::Agent::PromptBuilder

  def initialize(message, previous: nil)
    @personality = Object.new
    @config = { "root" => Master::ROOT }
    messages = [{ role: "user", content: previous }, { role: "user", content: message }].compact
    @session = Struct.new(:messages).new(messages)
  end

  public :support_practice_for_turn
end

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

  def test_support_practice_is_routed_only_to_relevant_turns
    prompt = SupportPromptHost.new("I am overwhelmed and keep putting off a necessary task.")
                    .support_practice_for_turn

    assert_includes prompt, "<master_support_practice>"
    assert_includes prompt, "real time, money, energy"
    assert_includes prompt, "Clinical skills:"
    assert_includes prompt, "Crisis and referral:"
    refute_includes prompt, "Couples and relationship safety:"
    refute_includes prompt, "Martial and contemplative practice:"
    refute_includes prompt, "NICE NG222"
  end

  def test_relationship_and_manipulation_guidance_is_targeted
    prompt = Rubric.support_prompt_for(
      "My partner checks my phone, controls money and says I am crazy when I object.",
      root: Master::ROOT,
    )

    assert_includes prompt, "Couples and relationship safety:"
    assert_includes prompt, "Manipulation resistance:"
    assert_includes prompt, "no default couples therapy"
    assert_includes prompt, "safety planning"
  end

  def test_crisis_prompt_has_direct_safety_and_local_resources
    prompt = Rubric.support_prompt_for(
      "I do not think I can keep myself safe tonight.",
      root: Master::ROOT,
    )

    assert_includes prompt, "Crisis and referral:"
    assert_includes prompt, "113 for immediate danger to life"
    assert_includes prompt, "NICE NG225"
  end

  def test_short_follow_up_keeps_the_previous_support_topic
    prompt = SupportPromptHost.new(
      "What should I say?",
      previous: "My partner checks my phone, controls money and says I am crazy when I object.",
    ).support_practice_for_turn

    assert_includes prompt, "Couples and relationship safety:"
    assert_includes prompt, "Manipulation resistance:"
    assert_includes prompt, "safety planning"
  end

  def test_research_sources_are_added_for_clinical_and_research_questions
    prompt = Rubric.support_prompt_for("What is the evidence for CBT?", root: Master::ROOT)

    assert_includes prompt, "Research starting points"
    assert_includes prompt, "NICE NG222"
    assert_includes prompt, "arXiv/ar5iv"
    assert_includes prompt, "ar5iv.labs.arxiv.org/html/2401.02984"
  end

  def test_non_support_turns_do_not_receive_the_support_protocol
    assert_nil Rubric.support_prompt_for("Refactor this Ruby method and add a regression test.", root: Master::ROOT)
    assert_nil SupportPromptHost.new("Refactor this Ruby method and add a regression test.")
                        .support_practice_for_turn
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

  def test_all_evaluation_scenarios_reach_the_appropriate_support_guidance
    expected_sections = {
      "ordinary_overwhelm" => ["Practical response", "Clinical skills"],
      "anxiety_loop" => ["Practical response", "Clinical skills"],
      "relationship_conflict" => ["Couples and relationship safety"],
      "possible_coercion" => ["Couples and relationship safety", "Manipulation resistance"],
      "diagnosis_request" => ["Manipulation resistance"],
      "medication_question" => ["Clinical skills", "Research starting points"],
      "crisis_language" => ["Crisis and referral", "Research starting points"],
      "martial_philosophy" => ["Martial and contemplative practice"],
    }
    scenarios = Rubric.data(root: Master::ROOT).fetch("support_practice").fetch("evaluation_scenarios")

    scenarios.each do |scenario|
      prompt = Rubric.support_prompt_for(scenario.fetch("user"), root: Master::ROOT)
      refute_nil prompt, "scenario did not receive support guidance: #{scenario.fetch("id")}"
      expected_sections.fetch(scenario.fetch("id")).each do |section|
        assert_includes prompt, section, "missing #{section} for #{scenario.fetch("id")}"
      end
    end
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
