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

  def test_integrations_catalog_contains_openclaw_stack
    path = File.join(MASTER.root, "data", "integrations.yml")
    assert File.exist?(path)

    catalog = YAML.safe_load_file(path)
    repos = Array(catalog["repos"])
    names = repos.map { |r| r["name"] }

    assert_operator repos.size, :>=, 10
    assert_includes names, "openclaw"
    assert_includes names, "astrbot"
    assert_includes names, "telegram_link_summarizer_agent"
  end
end
