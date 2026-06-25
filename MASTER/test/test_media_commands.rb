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

  def test_dilla_command_publishes_client_action
    bus = FakeBus.new
    out = Master::Now::CommandRegistry.dispatch_dilla(bus)
    assert_includes out, "Dilla"
    event, payload = bus.events.last
    assert_equal "client_action", event
    assert_equal "dilla_bg", payload[:action]
  end

  def test_radio_command_publishes_client_action
    bus = FakeBus.new
    out = Master::Now::CommandRegistry.dispatch_radio(bus)
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
    assert_equal "dilla", result.value!.command
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
    assert_equal "radio", result.value!.command
  end

  def test_play_dilla_not_classified_as_chitchat
    router = Master::Now::Routing::ModelRouter.new(
      config: Struct.new(:model).new("z-ai/glm-4.5-air:free"),
      root: Master::ROOT
    )
    refute_equal :chitchat, router.classify_intent("play j dilla beats")
  end

  def test_video_command_registered
    cmds = Master::Now::CommandRegistry.tool_commands(Master::ROOT, nil)
    assert cmds.key?("video")
  end

  def test_video_usage_without_prompt
    out = Master::Now::CommandRegistry.dispatch_video(Master::ROOT, nil)
    assert_includes out, "usage: /video"
    assert_includes out, "minimax/video-01-live"
  end
end