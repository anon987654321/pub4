# frozen_string_literal: true

require_relative "test_helper"

class CLIBridgeTest < Minitest::Test
  # See test_cli.rb: building a CLI with a tokenless config leaves
  # Fiber[:master_visitor] set for the rest of the process.
  def teardown
    Fiber[:master_visitor] = nil
  end

  def build_cli(commands: nil, pipeline: Object.new)
    unless pipeline.respond_to?(:last_timings)
      pipeline.define_singleton_method(:last_timings) { nil }
    end
    renderer = Object.new
    renderer.define_singleton_method(:render) { |text, **| text }
    renderer.define_singleton_method(:speaker_tag) { "agent> " }
    agent = Struct.new(:model).new("test-model")
    session = Struct.new(:budget_max, :cost, :token_est, :tokens_billed, :phase, :messages).new(0, 0.0, 0, 0, :work, [])
    Master::CLI::Session.new(
      container: {
        session:,
        agent:,
        renderer:,
        logging: Object.new,
        undo: Object.new,
        config: {},
        pipeline:,
        commands: commands || {
          "status" => Master::CLI::CommandRegistry::Command.new { "status-ok" },
        },
        root: Dir.pwd,
        bus: nil,
      },
    )
  end

  def test_run_input_uses_turn_router_for_plain_language
    pipeline = Object.new
    pipeline.define_singleton_method(:call) { raise "pipeline should not run" }
    cli = build_cli(pipeline:)
    fold = { reason: :complete, turns: 2, summary: "ok", transcript: ["1: done -> ok"] }

    Master.stub(:any_api_key_present?, true) do
      Master::CLI::TurnRouter.stub(:call, Master::Result.ok(output: "core: complete turns=2\nok", rendered: "core: complete turns=2\nok", core: fold)) do
        out, = capture_io { cli.run_input("write a note") }
        assert_match(/core: complete turns=2/, out)
        assert_match(/ok/, out)
      end
    end
  end

  def test_run_input_dispatches_slash_without_pipeline
    calls = []
    pipeline = Object.new
    pipeline.define_singleton_method(:call) { |*| calls << :pipeline; Master::Result.ok(output: "legacy") }
    cli = build_cli(pipeline:)

    out, = capture_io { cli.run_input("/status") }
    assert_match(/status-ok/, out)
    assert_empty calls
  end

  def test_run_agent_turn_skips_workflow_fanout
    cli = build_cli
    fold = { reason: :complete, turns: 1, summary: "fixed", transcript: [] }
    routed = nil
    cli.define_singleton_method(:run_input) { |line| routed = line }

    Master.stub(:any_api_key_present?, true) do
      cli.send(:run_agent_turn, "scan lib then fix and commit")
      assert_equal "scan lib then fix and commit", routed
    end
  end
end
