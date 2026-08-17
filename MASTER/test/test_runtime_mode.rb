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

  # What matters is that PIPELINE_STAGES agrees with the assembly, not with any
  # particular literal. TurnRouter assembles a turn, so these read TurnRouter.
  TURN_ROUTER = File.join(Master::ROOT, "lib", "cli", "turn_router.rb")

  def constructed_stages
    File.read(TURN_ROUTER).scan(/Stages::(\w+)\.new/).flatten.uniq
  end

  def named_stages
    Master::CLI::RuntimeMode::PIPELINE_STAGES.split("→").map(&:strip)
  end

  def test_every_named_pipeline_stage_is_one_turnrouter_constructs
    missing = named_stages - constructed_stages
    assert_empty missing,
                 "PIPELINE_STAGES names #{missing.join(", ")}, which TurnRouter never constructs — " \
                 "the string is served to agents as orientation, so it has to be the live sequence"
  end

  def test_every_stage_turnrouter_constructs_is_named
    unnamed = constructed_stages - named_stages
    assert_empty unnamed,
                 "TurnRouter constructs #{unnamed.join(", ")} and PIPELINE_STAGES does not say so"
  end

  def test_named_pipeline_stages_are_in_the_order_turnrouter_runs_them
    assert_equal constructed_stages.sort, named_stages.sort
    assert_equal "Intake", named_stages.first, "a turn starts at Intake"
    assert_equal "Render", named_stages.last, "a turn ends at Render"
  end

  def test_agents_bootstrap_names_directories_that_exist
    line = Master::Ground::BootstrapDocs::AGENTS.lines.find { |l| l.start_with?("Modules:") }
    refute_nil line, "the agent bootstrap no longer names its modules"
    named = line.sub("Modules:", "").split(",").map { |m| m.strip[/\A\w+/] }.compact
    missing = named.reject { |m| Dir.exist?(File.join(Master::ROOT, "lib", m)) }
    assert_empty missing, "the agent bootstrap names lib/ directories that do not exist: #{missing.join(", ")}"
  end

  def test_tools_command_lists_registered_tools
    output = Master::CLI::CommandRegistry.dispatch_tools(Master::ROOT, nil, ctx: { args: "" })
    assert_includes output, "ReadFile"
    assert_includes output, "io"
  end
end
