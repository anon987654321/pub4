# frozen_string_literal: true

require "minitest/autorun"
require_relative "../../lib/master"
require_relative "../../lib/cli/pipeline"
require_relative "../../lib/cli/pipeline_context"
require_relative "../../lib/cli/stages/intake"

class PipelineE2eSpec < Minitest::Test
  class EchoStage
    def call(ctx) = Master::Result.ok(ctx.merge(output: "echo: #{ctx.user_message}"))
  end

  class FailStage
    def call(_ctx) = Master::Result.err("deliberate failure", category: :validation)
  end

  class RecordStage
    attr_reader :calls

    def initialize = @calls = []
    def call(ctx) = (@calls << ctx.user_message; Master::Result.ok(ctx))
  end

  def build_pipeline(*stages)
    Master::CLI::Pipeline.new(stages)
  end

  def ctx(message = "hello")
    Master::CLI::PipelineContext.build(user_message: message)
  end

  def test_result_chain_propagates_ok_through_all_stages
    recorder = RecordStage.new
    result = build_pipeline(recorder, EchoStage.new).call(ctx)
    assert result.ok?
    assert_equal "echo: hello", result.value[:output]
    assert_equal ["hello"], recorder.calls
  end

  def test_result_chain_short_circuits_on_error
    recorder = RecordStage.new
    result = build_pipeline(FailStage.new, recorder).call(ctx)
    refute result.ok?
    assert_empty recorder.calls
  end

  def test_error_carries_category
    result = build_pipeline(FailStage.new).call(ctx)
    refute result.ok?
    assert_match(/deliberate/, result.message)
  end

  def test_intake_parses_slash_command
    result = build_pipeline(Master::CLI::Stages::Intake.new).call(ctx("/scan lib/"))
    assert result.ok?, result.inspect
    assert_equal :command, result.value[:intent]
    assert_equal "scan",   result.value[:command]
    assert_equal "lib/",   result.value[:args]
  end

  def test_intake_parses_plain_text_as_llm_intent
    result = build_pipeline(Master::CLI::Stages::Intake.new).call(ctx("what is fix_loop for?"))
    assert result.ok?, result.inspect
    assert_equal :llm, result.value[:intent]
  end

  def test_intake_rejects_empty_message
    result = build_pipeline(Master::CLI::Stages::Intake.new).call(ctx("   "))
    refute result.ok?
    assert_match(/empty/, result.message)
  end

  def test_intake_followed_by_echo_stage
    result = build_pipeline(Master::CLI::Stages::Intake.new, EchoStage.new).call(ctx("hello world"))
    assert result.ok?, result.inspect
    assert_equal :llm,          result.value[:intent]
    assert_equal "echo: hello world", result.value[:output]
  end
end
