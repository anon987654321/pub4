# frozen_string_literal: true

require_relative "test_helper"

class TestDestructiveRoutes < Minitest::Test
  def test_destructive_commands_include_infer_defaults
    commands = Master::CLI::DestructiveRoutes.destructive_commands
    %w[clear rebuild resync shell rollback].each do |cmd|
      assert_includes commands, cmd
    end
  end

  def test_destructive_route_detects_slash_command
    ctx = Master::CLI::PipelineContext.build(user_message: "/shell ls", intent: :command, command: "shell")
    assert Master::CLI::DestructiveRoutes.destructive_route?(ctx)
  end

  def test_destructive_route_detects_dangerous_tool_tier
    ctx = Master::CLI::PipelineContext.build(user_message: "run", intent: :llm, last_tool_tier: :dangerous)
    assert Master::CLI::DestructiveRoutes.destructive_route?(ctx)
  end

  def test_blocking_review_respects_env_opt_out
    previous = ENV["MASTER_BLOCKING_REVIEW"]
    ENV["MASTER_BLOCKING_REVIEW"] = "0"
    assert_equal false, Master::CLI::DestructiveRoutes.blocking_review?
  ensure
    ENV["MASTER_BLOCKING_REVIEW"] = previous
  end
end
