# frozen_string_literal: true

require_relative "test_helper"

class TurnRouterTest < Minitest::Test
  def build_container(commands: nil)
    renderer = Object.new
    renderer.define_singleton_method(:render) { |text, **| text }
    {
      session: Struct.new(:budget_max, :cost).new(0, 0.0),
      agent: Struct.new(:model).new("test-model"),
      renderer:,
      commands: commands || { "status" => Master::CLI::CommandRegistry::Command.new { "status-ok" } },
      root: Dir.pwd,
      bus: nil,
    }
  end

  # A coding goal that Infer does not promote to an operator command: "fix the
  # bug" now routes to /fix via THROUGH_COMMANDS, so it no longer reaches the
  # Fold. This message stays plain language all the way down.
  def test_plain_language_routes_to_fold
    fold = { reason: :complete, turns: 1, summary: "done", transcript: [] }
    Master.stub(:any_api_key_present?, true) do
      Master::CLI::CoreBridge.stub(:run, fold) do
        result = Master::CLI::TurnRouter.call(message: "implement pagination for posts", container: build_container)
        assert result.ok?
        assert_match(/core: complete/, result.value[:rendered])
      end
    end
  end

  def test_fix_language_is_promoted_to_operator_command_not_fold
    inferred = Master::CLI::TurnRouter.infer_operator_command("fix the bug", container: build_container)

    refute_nil inferred, "expected Infer to promote 'fix the bug' to an operator command"
    assert_includes Master::CLI::TurnRouter::THROUGH_COMMANDS, inferred[:command]
  end

  def test_slash_routes_to_command_registry
    calls = []
    pipeline = Object.new
    pipeline.define_singleton_method(:call) { |*| calls << :pipeline }
    Master::CLI::TurnRouter.call(message: "/status", container: build_container)
    assert_empty calls
  end

  def test_slash_status_renders_command_output
    result = Master::CLI::TurnRouter.call(message: "/status", container: build_container)
    assert result.ok?
    assert_match(/status-ok/, result.value[:rendered].to_s)
  end

  def test_run_promotes_to_fold
    fold = { reason: :complete, turns: 1, summary: "shipped", transcript: [] }
    Master.stub(:any_api_key_present?, true) do
      Master::CLI::CoreBridge.stub(:run, fold) do
        result = Master::CLI::TurnRouter.call(message: "/run add tests", container: build_container)
        assert result.ok?
        assert_match(/shipped/, result.value[:rendered])
      end
    end
  end
end
