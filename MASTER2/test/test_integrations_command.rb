# frozen_string_literal: true

require_relative "test_helper"

class TestIntegrationsCommand < Minitest::Test
  def test_integrations_command_is_routed
    table = MASTER::Commands::COMMAND_TABLE
    assert_equal [:integrations, true], table["integrations"]
    assert_equal [:integrations, true], table["integration"]
  end

  def test_integrations_method_exists
    assert MASTER::Commands.respond_to?(:integrations, true)
  end

  def test_integrations_catalog_is_high_signal_curated
    path = File.join(MASTER.root, "data", "integrations.yml")
    assert File.exist?(path)

    catalog = YAML.safe_load_file(path)
    repos = Array(catalog["repos"])
    names = repos.map { |r| r["name"] }

    assert_equal "openclaw_telegram_local_ai_high_signal", catalog["profile"]
    assert_operator repos.size, :<=, 8
    assert_includes names, "litellm"
    assert_includes names, "openclaw"
    assert_includes names, "opencrabs"
    assert_includes names, "astrbot"
    assert_includes names, "docsgpt"
    refute_includes names, "openrouter_bot"
    refute_includes names, "500_ai_agents_projects"
    refute_includes names, "awesome_ai_agents"
  end
end
