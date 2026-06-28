# frozen_string_literal: true

require_relative "test_helper"

class TestMediaCommands < Minitest::Test
  class FakeBus
    attr_reader :events

    def initialize
      @events = []
    end

    def publish(event, payload = {})
      @events << [event, payload]
    end
  end

  class FakeAgent
    attr_reader :last_system

    def ask_once(seed, system:)
      @last_system = system
      "In summary, perhaps #{seed} — golden hour rim light, slow dolly, cinematic motion."
    end

    def ask(seed, system:, image: nil)
      ask_once(seed, system: system)
    end
  end

  def test_music_dilla_publishes_client_action
    bus = FakeBus.new
    out = Master::Now::CommandRegistry.dispatch_music(bus)
    assert_includes out, "Dilla"
    event, payload = bus.events.last
    assert_equal "client_action", event
    assert_equal "dilla_bg", payload[:action]
  end

  def test_music_radio_publishes_client_action
    bus = FakeBus.new
    out = Master::Now::CommandRegistry.dispatch_music(bus, ctx: { args: "radio" })
    assert_includes out, "Radio Bergen"
    event, payload = bus.events.last
    assert_equal "client_action", event
    assert_equal "radio_open", payload[:action]
  end

  def test_infer_promotes_play_j_dilla
    bus = FakeBus.new
    infer = Master::Now::Stages::Infer.new(bus: bus)
    result = infer.call(Master::Now::PipelineContext.build(
      user_message: "play j dilla",
      intent: :llm,
      message: "play j dilla"
    ))
    assert result.ok?
    assert_equal :command, result.value!.intent
    assert_equal "music", result.value!.command
    assert_equal "", result.value!.args
  end

  def test_infer_promotes_radio_bergen
    bus = FakeBus.new
    infer = Master::Now::Stages::Infer.new(bus: bus)
    result = infer.call(Master::Now::PipelineContext.build(
      user_message: "open radio bergen",
      intent: :llm,
      message: "open radio bergen"
    ))
    assert result.ok?
    assert_equal :command, result.value!.intent
    assert_equal "music", result.value!.command
    assert_equal "radio", result.value!.args
  end

  def test_play_dilla_not_classified_as_chitchat
    router = Master::Now::Routing::ModelRouter.new(
      config: Struct.new(:model).new("z-ai/glm-4.5-air:free"),
      root: Master::ROOT
    )
    refute_equal :chitchat, router.classify_intent("play j dilla beats")
  end

  def test_music_command_registered
    cmds = Master::Now::CommandRegistry.media_commands
    assert cmds.key?("music")
  end

  def test_media_tool_commands_registered
    cmds = Master::Now::CommandRegistry.tool_commands(Master::ROOT, nil)
    %w[repligen photograph prompt video motion-dataset lora-train social-sim].each do |name|
      assert cmds.key?(name), "expected /#{name} in tool_commands"
    end
  end

  def test_infer_promotes_video_generate
    bus = FakeBus.new
    infer = Master::Now::Stages::Infer.new(bus: bus)
    result = infer.call(Master::Now::PipelineContext.build(
      user_message: "generate a cinematic video of neon rain chase",
      intent: :llm,
      message: "generate a cinematic video of neon rain chase"
    ))
    assert result.ok?
    assert_equal :command, result.value!.intent
    assert_equal "video", result.value!.command
  end

  def test_refine_repligen_video_generate_arg
    agent = FakeAgent.new
    arg = "generate minimax/video-01-live harbor at dawn"
    refined = Master::Reach::RepligenArg.refine_generate(arg, agent: agent)
    assert refined.start_with?("generate minimax/video-01-live ")
    refute_equal arg, refined
    assert_match(/harbor/i, refined)
    assert_includes agent.last_system, "text-to-video"
  end

  def test_refine_repligen_skips_unknown_models
    agent = FakeAgent.new
    arg = "generate some-model test prompt"
    assert_equal arg, Master::Reach::RepligenArg.refine_generate(arg, agent: agent)
  end
end