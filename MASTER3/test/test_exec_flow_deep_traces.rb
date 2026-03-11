# frozen_string_literal: true

require_relative "test_helper"

class TestMaster3ExecFlowDeepTraces < Minitest::Test
  DummyConfig = Struct.new(:auto_testing?)

  class PassGuard
    def scan(_msg) = Master3::Result.ok(:clear)
  end

  class PlainRenderer
    def render(text, mode: :plain) = "[#{mode}] #{text}"
  end

  def build_pipeline(event_bus: nil)
    commands = {
      "trace" => lambda { |ctx|
        event_bus&.publish("exec:trace", command: ctx[:command], args: ctx[:args])
        "Certainly. I think that trace complete. I hope this helps."
      }
    }

    stages = [
      Master3::Stages::Intake.new,
      Master3::Stages::Route.new(commands:, agent: ->(_ctx) { "agent reply" }),
      Master3::Stages::Guard.new(governor: Object.new, injection_guard: PassGuard.new),
      Master3::Stages::Execute.new,
      Master3::Stages::Strunk.new,
      Master3::Stages::Render.new(renderer: PlainRenderer.new)
    ]

    Master3::Pipeline.new(stages)
  end

  def test_command_execution_flow_emits_trace_and_cleans_output
    ring = Master3::RingBuffer.new(20)
    bus = Master3::EventBus.new(log: ring)
    logging = Master3::Logging.new(ring_buffer: ring, event_bus: bus)
    pipeline = build_pipeline(event_bus: bus)

    result = pipeline.call(Master3::Result.ok(user_message: "/trace --deep"))

    assert result.ok?
    rendered = result.value[:rendered]
    assert_includes rendered, "trace complete."
    refute_includes rendered, "Certainly."
    refute_includes rendered, "I think that"

    entries = []
    ring.each { |line| entries << line }
    dmesg = entries.join("\n")
    assert_includes dmesg, "exec:trace"
    assert_includes dmesg, "--deep"
  end

  def test_unknown_command_is_validation_error_edge_case
    pipeline = build_pipeline

    result = pipeline.call(Master3::Result.ok(user_message: "/missing"))

    assert result.err?
    assert_equal :validation, result.category
    assert_match %r{unknown command: /missing}, result.message
  end

  def test_execute_stage_survives_handler_exceptions
    execute = Master3::Stages::Execute.new

    result = execute.call(handler: ->(_ctx) { raise "kaboom" })

    assert result.err?
    assert_equal :unknown, result.category
    assert_match(/execute: kaboom/, result.message)
  end
end
