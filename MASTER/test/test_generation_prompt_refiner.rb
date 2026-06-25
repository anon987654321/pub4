# frozen_string_literal: true

require_relative "test_helper"

class TestGenerationPromptRefiner < Minitest::Test
  class FakeAgent
    attr_reader :last_system

    def ask_once(seed, system:)
      @last_system = system
      "In summary, perhaps #{seed} — golden hour rim light, 85mm f/1.4, Kodak Portra grain."
    end

    def ask(seed, system:, image:)
      @last_system = system
      "I think that #{seed} with reference palette and mist rolling through fjord valleys."
    end
  end

  def test_strunk_pass_strips_hedges_and_preambles
    input = "In summary, I think that perhaps fog over Bergen at dawn."
    output = Master::Voice::StrunkPass.call(input)

    refute_match(/In summary/i, output)
    refute_match(/I think that/i, output)
    refute_match(/perhaps/i, output)
    assert_match(/Bergen/i, output)
  end

  def test_refiner_expands_and_strunk_polishes_photo_seed
    agent = FakeAgent.new
    out = Master::Reach::GenerationPromptRefiner.refine(
      prompt: "fog over Bergen",
      medium: :photo,
      agent: agent
    )

    assert_includes agent.last_system, "Flux"
    assert_includes agent.last_system, "Strunk"
    refute_match(/perhaps/i, out)
    assert_match(/Bergen/i, out)
    assert_operator out.length, :>, 20
  end

  def test_refiner_uses_video_system
    agent = FakeAgent.new
    out = Master::Reach::GenerationPromptRefiner.refine(
      prompt: "harbor at dawn",
      medium: :video,
      agent: agent
    )

    assert_includes agent.last_system, "text-to-video"
    assert_match(/harbor/i, out)
  end

  def test_refiner_without_agent_returns_seed
    seed = "minimal seed"
    assert_equal seed, Master::Reach::GenerationPromptRefiner.refine(prompt: seed, medium: :photo, agent: nil)
  end

  def test_dispatch_prompt_usage
    out = Master::Now::CommandRegistry.dispatch_prompt(Master::ROOT, nil)
    assert_includes out, "usage: /prompt"
  end

  def test_dispatch_prompt_photo_medium
    agent = FakeAgent.new
    out = Master::Now::CommandRegistry.dispatch_prompt(Master::ROOT, agent, ctx: { args: "photo misty pier" })
    assert_includes out, "medium=photo"
    assert_includes out, "seed: misty pier"
    assert_includes out, "refined:"
  end

  class FakeBus
    def publish(*) = nil
  end

  def test_infer_promotes_write_prompt_for
    bus = FakeBus.new
    infer = Master::Now::Stages::Infer.new(bus: bus)
    result = infer.call(Master::Now::PipelineContext.build(
      user_message: "expand and embellish a photo prompt for fog over Bergen harbor",
      intent: :llm,
      message: "expand and embellish a photo prompt for fog over Bergen harbor"
    ))
    assert result.ok?
    assert_equal :command, result.value!.intent
    assert_equal "prompt", result.value!.command
    assert_includes result.value!.args, "Bergen"
  end
end