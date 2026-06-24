# frozen_string_literal: true

require_relative "test_helper"

class InferStageTest < Minitest::Test
  class FakeBus
    attr_reader :events

    def initialize
      @events = []
    end

    def publish(event, payload = {})
      @events << [event, payload]
    end
  end

  def setup
    @bus = FakeBus.new
    @infer = Master::Now::Stages::Infer.new(bus: @bus)
  end

  def ctx(message, intent: :llm, **extra)
    Master::Now::PipelineContext.build(user_message: message, intent: intent, message: message, **extra)
  end

  def test_promotes_scan_natural_language
    result = @infer.call(ctx("please scan deep lib/"))
    assert result.ok?
    out = result.value!
    assert_equal :command, out.intent
    assert_equal "scan", out.command
    assert_equal "deep", out.args
    assert_equal "scan", out.inferred_command
  end

  def test_explain_alias_maps_to_orient
    result = @infer.call(ctx("explain your architecture"))
    assert result.ok?
    out = result.value!
    assert_equal :command, out.intent
    assert_equal "orient", out.command
    assert_equal "orient", out.inferred_command
  end

  def test_publishes_infer_resolved
    @infer.call(ctx("how much did this cost"))
    event, payload = @bus.events.find { |ev, _| ev == "infer:resolved" }
    assert_equal "infer:resolved", event
    assert_equal "cost", payload[:command]
    assert payload[:confidence].to_f.positive?
    conf_event = @bus.events.find { |ev, _| ev == "infer:confidence" }
    refute_nil conf_event
  end

  def test_negative_pattern_blocks_risky_scan
    result = @infer.call(ctx("scan my email inbox"))
    assert result.ok?
    assert_equal :llm, result.value!.intent
    rejected = @bus.events.find { |ev, _| ev == "infer:rejected" }
    refute_nil rejected
  end

  def test_detects_coding_task_type
    result = @infer.call(ctx("fix the bug in lib/foo.rb"))
    assert result.ok?
    assert_equal :coding, result.value!.task_type
  end

  def test_skips_command_intent
    result = @infer.call(ctx("/scan lib", intent: :command, command: "scan", args: "lib"))
    assert result.ok?
    assert_equal :command, result.value!.intent
    assert_nil result.value!.inferred_command
    assert_empty @bus.events
  end

  def test_plain_llm_passes_through
    result = @infer.call(ctx("tell me a joke about compilers"))
    assert result.ok?
    out = result.value!
    assert_equal :llm, out.intent
    assert_equal :general, out.task_type
  end
end