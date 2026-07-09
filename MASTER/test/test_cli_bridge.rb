# frozen_string_literal: true

require_relative "test_helper"
class CLIBridgeTest < Minitest::Test
  def build_cli(pipeline:)
    unless pipeline.respond_to?(:last_timings)
      pipeline.define_singleton_method(:last_timings) { nil }
    end
    renderer = Object.new
    renderer.define_singleton_method(:render) { |text, **| text }
    renderer.define_singleton_method(:speaker_tag) { "agent> " }
    agent = Struct.new(:model).new("test-model")
    session = Struct.new(:budget_max, :cost, :token_est, :phase, :messages).new(0, 0.0, 0, :work, [])
    Master::Now::CLI.new(
      container: {
        session:,
        agent:,
        renderer:,
        logging: Object.new,
        undo: Object.new,
        config: {},
        pipeline:,
        root: Dir.pwd,
        bus: nil
      }
    )
  end

  def test_bridge_agent_turn_for_plain_language
    cli = build_cli(pipeline: Object.new)
    assert cli.send(:bridge_agent_turn?, "add a health check")
    refute cli.send(:bridge_agent_turn?, "/scan lib")
  end

  def test_bridge_agent_turn_respects_legacy_pipeline_env
    cli = build_cli(pipeline: Object.new)
    prior = ENV["MASTER_LEGACY_PIPELINE"]
    ENV["MASTER_LEGACY_PIPELINE"] = "1"
    refute cli.send(:bridge_agent_turn?, "add a health check")
  ensure
    if prior
      ENV["MASTER_LEGACY_PIPELINE"] = prior
    else
      ENV.delete("MASTER_LEGACY_PIPELINE")
    end
  end

  def test_run_input_uses_core_bridge_for_plain_language
    pipeline = Object.new
    pipeline.define_singleton_method(:call) { raise "pipeline should not run" }
    cli = build_cli(pipeline:)
    fold = { reason: :complete, turns: 2, summary: "ok", transcript: ["1: done -> ok"] }

    Master.stub(:any_api_key_present?, true) do
      Master::Now::CoreBridge.stub(:run, fold) do
        out, = capture_io { cli.run_input("write a note") }
        assert_match(/core: complete turns=2/, out)
        assert_match(/ok/, out)
      end
    end
  end

  def test_run_input_uses_pipeline_for_slash_commands
    calls = []
    pipeline = Object.new
    pipeline.define_singleton_method(:call) do |initial|
      calls << initial
      Master::Result.ok(output: "scanned")
    end
    cli = build_cli(pipeline:)

    out, = capture_io { cli.run_input("/scan lib") }
    assert_match(/scanned/, out)
    assert_equal 1, calls.size
  end

  def test_run_core_bridge_input_maps_complete_fold_to_ok
    cli = build_cli(pipeline: Object.new)
    fold = { reason: :complete, turns: 1, summary: "note written", transcript: [] }

    Master.stub(:any_api_key_present?, true) do
      Master::Now::CoreBridge.stub(:run, fold) do
        state = { streamed: false, thinking_shown: true }
        result = cli.send(:run_core_bridge_input, "write note.txt", state:, accumulated: +"")
        assert result.ok?
        assert_match(/core: complete/, result.value[:output])
        assert_match(/note written/, result.value[:output])
      end
    end
  end

  def test_run_core_bridge_input_maps_max_turns_to_err
    cli = build_cli(pipeline: Object.new)
    fold = { reason: :max_turns, turns: 40, summary: nil, transcript: ["40: write -> blocked"] }

    Master.stub(:any_api_key_present?, true) do
      Master::Now::CoreBridge.stub(:run, fold) do
        state = { streamed: false, thinking_shown: true }
        result = cli.send(:run_core_bridge_input, "never finish", state:, accumulated: +"")
        refute result.ok?
        assert_equal :policy, result.category
      end
    end
  end
end