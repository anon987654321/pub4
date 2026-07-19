# frozen_string_literal: true

require_relative "test_helper"

class TurnPipelineTest < Minitest::Test
  def build_container
    renderer = Object.new
    renderer.define_singleton_method(:render) { |text, **| text }
    {
      agent: Struct.new(:model).new("test"),
      renderer:,
      commands: { "status" => Master::CLI::CommandRegistry::Command.new { "ok-status" } },
      root: Dir.pwd,
      bus: nil
    }
  end

  def test_call_dispatches_slash_via_turn_router
    pipeline = Master::CLI::TurnPipeline.new(container: build_container)
    result = pipeline.call(Master::Result.ok(user_message: "/status"))
    assert result.ok?
    assert_match(/ok-status/, result.value[:rendered].to_s)
  end

  def test_last_timings_empty
    pipeline = Master::CLI::TurnPipeline.new(container: build_container)
    assert_equal({}, pipeline.last_timings)
  end
end
