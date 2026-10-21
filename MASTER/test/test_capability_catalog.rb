# frozen_string_literal: true

require_relative "test_helper"

class CapabilityCatalogTest < Minitest::Test
  Catalog = Master::Ground::CapabilityCatalog

  def test_catalog_distinguishes_core_tools_from_plugin_integration_units
    result = Catalog.call(action: "list")

    assert_equal "ok", result.fetch("status")
    assert result.fetch("core_tools").any? { |tool| tool["name"] == "ReadFile" && tool["elevated_required"] == false }
    plugin = result.fetch("plugins").find { |item| item["id"] == "session_browser" }
    assert plugin
    assert_equal %w[status inspect], plugin.fetch("observation_actions").map { |row| row["name"] }
    assert plugin.fetch("observation_actions").all? { |row| row["access"] == "read_only" }
    assert_includes %w[declared policy_missing no_observation_actions], plugin.fetch("status")
    assert_match(/not proof of live availability/, result.fetch("note"))
  end

  def test_search_returns_matching_tools_and_plugins
    result = Catalog.call(action: "search", query: "browser")
    names = result.fetch("results").map { |item| item["name"] || item["id"] }

    assert_includes names, "Browser"
    assert_includes names, "session_browser"
  end

  def test_describe_supports_a_builtin_tool_plugin_and_declared_action
    assert_equal "core_tool", Catalog.call(action: "describe", name: "ReadFile").fetch("kind")
    assert_equal "plugin", Catalog.call(action: "describe", name: "session_browser").fetch("kind")
    result = Catalog.call(action: "describe", name: "plugin:session_browser:status")
    assert_equal "plugin_observation", result.fetch("kind")
    assert_equal "read_only", result.fetch("capability").fetch("access")
  end

  def test_unknown_descriptions_and_empty_search_are_explicit
    assert_equal "not_found", Catalog.call(action: "describe", name: "not_registered").fetch("status")
    assert_raises(ArgumentError) { Catalog.call(action: "search", query: " ") }
    assert_raises(ArgumentError) { Catalog.call(action: "execute", name: "Browser") }
  end
end
