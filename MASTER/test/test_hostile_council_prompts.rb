# frozen_string_literal: true

require_relative "test_helper"
require "master"

# Each council stage is asked to attack its own conclusion before it becomes a
# finding. These build the prompts the stages send and read what they say.
class HostileCouncilPromptsTest < Minitest::Test
  Persona = Struct.new(:name, :role, :bias, :prompt, :veto_role, :emphasizes, keyword_init: true) do
    def veto? = !!veto_role
  end

  FEEDBACK = [{ persona: "Skeptic", feedback: "the nav wraps on narrow phones" }].freeze

  # Never asked: the prompt is built, not sent.
  class SilentAgent
    def ask(*, **) = raise("the prompt test sent a prompt")
  end

  def test_juror_prompt_exposes_self_falsification
    persona = Persona.new(name: "Skeptic", role: "Doubter", bias: "none", prompt: "be sceptical")
    delib = Master::Review::Council::Deliberation.new(personas: [persona], agent: SilentAgent.new, judge_enabled: false)
    prompt = delib.send(:build_prompt, persona:, code: "x = 1", context: nil)

    questions = Master::Review::Council::QualityFramework.hostile_questions(persona)
    refute_empty questions, "council.yml declares no red_team questions"
    assert_includes prompt, "HOSTILE SELF-TEST"
    assert_includes prompt, "what evidence would falsify your criticism"
    questions.each { |question| assert_includes prompt, "- #{question}" }
  end

  def test_solution_generation_attacks_the_field_before_cherry_pick
    critic = Master::Review::Council::Critique.new(mode: :general, agent: nil, files: [])
    prompt = critic.send(:ideation_prompt, FEEDBACK)

    assert_includes prompt, "SOLUTION RED-TEAM"
    %w[hidden\ assumption smallest\ deletion counterexample\ state invert\ that\ assumption].each do |phrase|
      assert_includes prompt, phrase
    end
    assert_operator prompt.index("SOLUTION RED-TEAM"), :<, prompt.index("1. the nav wraps on narrow phones"),
                    "the red-team comes after the issues it should shape"
  end

  def test_visual_fix_adds_visual_counterfactuals
    pass = Master::Fix::VisualPass.new(agent: nil, root: File.expand_path("..", __dir__))
    context = pass.send(:build_context, [], {}, graph: nil)

    assert_includes context, "HOSTILE VISUAL AUDIT"
    assert_includes context, "font loading"
    assert_includes context, "adversarial user"
    assert_includes context, "Only promote a hostile observation"
  end
end
