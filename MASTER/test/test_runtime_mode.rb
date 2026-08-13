# frozen_string_literal: true

require_relative "test_helper"

class TestRuntimeMode < Minitest::Test
  def test_summary_includes_safe_and_visitor_defaults
    ENV["MASTER_SAFE_MODE"] = "1"
    ENV["MASTER_WEB"] = "0"
    line = Master::CLI::RuntimeMode.summary(config: { "web_token" => "" })
    assert_includes line, "safe"
    assert_includes line, "visitor"
    assert_includes line, "cli"
  end

  def test_pipeline_stages_match_plugin_assembly
    stages = Master::CLI::RuntimeMode::PIPELINE_STAGES
    assert_includes stages, "Deliberate"
    assert_includes stages, "Review"
    refute_includes stages, "Prune → Memo"
  end

  def test_orient_includes_reading_tiers_and_trace_pointer
    output = Master::CLI::CommandRegistry.dispatch_orient(Master::ROOT, ctx: { args: "" })
    assert_includes output, "reading tiers"
    assert_includes output, "/orient trace"
    assert_includes output, "pairing:"
    assert_includes output, "bundle exec ruby bin/cli"
    assert_includes output, "Deliberate"
  end

  def test_tools_command_lists_reach_tools
    output = Master::CLI::CommandRegistry.dispatch_tools(Master::ROOT, nil, ctx: { args: "" })
    assert_includes output, "ReadFile"
    assert_includes output, "reach"
  end
end
