# frozen_string_literal: true

require_relative "test_helper"

class TestPlugins < Minitest::Test
  def test_manifests_have_local_policy
    manifests = Master::Plugin.list
    assert_equal %w[air_superiority social_browser], manifests.map(&:id)
    manifests.each { |manifest| assert Master::Plugin.policy(manifest.id).is_a?(Hash) }
  end

  def test_social_sites_are_fixed_and_https_only
    plugin = Master::Plugin.load("social_browser")
    result = plugin.call(action: "status")
    assert_equal %w[onlyfans fetlife snapchat], result[:sites].map { |site| site[:id] }
    assert_includes %w[ferrum unavailable], result[:browser]
  end

  def test_social_does_not_admit_unsolicited_actions
    plugin = Master::Plugin.load("social_browser")
    assert_raises(Master::Plugin::PolicyError) do
      plugin.call(
        action: "publish_owned",
        site: "onlyfans",
        account: "test",
        url: "https://onlyfans.com",
        message: "x",
        consent: true,
        owned_account: false,
      )
    end
  end

  def test_air_refuses_unknown_actions
    plugin = Master::Plugin.load("air_superiority")
    assert_raises(Master::Plugin::PolicyError) { plugin.call(action: "inject") }
  end

  def test_air_runtime_is_truthful
    result = Master::Plugin.load("air_superiority").call(action: "status")
    assert result[:runtime]
    assert result[:wifi]
    assert result[:bluetooth]
  end

  def test_air_scan_marks_partial_results_explicitly
    plugin = Master::Plugin.load("air_superiority")
    result = plugin.send(:scan)
    assert_includes [true, false], result[:complete]
    assert result[:observed_at]
    assert_equal result[:wifi].length, result[:counts][:wifi]
    assert_equal result[:bluetooth].length, result[:counts][:bluetooth]
  end

  def test_air_analysis_uses_normalized_findings
    analyzer = Master::Plugins::AirSuperioritySupport::Analyzer.new(observed_at: Time.at(0).utc)
    findings = analyzer.wifi([{ "bssid" => "AA:BB:CC:DD:EE:FF", "ssid" => "test" }], [])
    assert_equal "unknown_wifi", findings.first.kind
    assert_equal "advisory", findings.first.severity
    assert_equal Time.at(0).utc, findings.first.observed_at
  end

  def test_observable_actions_are_declared_by_manifest
    assert_equal %w[status inspect], Master::Plugin.info("social_browser").observe_actions
    assert_equal %w[status scan], Master::Plugin.info("air_superiority").observe_actions
  end

  def test_observe_rejects_mutating_plugin_actions
    assert_raises(Master::Plugin::PolicyError) do
      Master::Plugin.observe("social_browser", action: "publish_owned")
    end
  end

  def test_plugin_observe_adapter_returns_observation_result
    governor = Object.new
    governor.define_singleton_method(:permit?) { |*| Master::Result.ok(true) }
    tool = Master::Io::PluginObserve.new(governor:, event_bus: nil)
    result = tool.call(plugin: "air_superiority", action: "status", args: {})
    assert result.ok?
    assert_equal "air_superiority", result.value!.fetch(:plugin)
  end

  def test_plugin_observe_rejects_non_object_arguments
    governor = Object.new
    governor.define_singleton_method(:permit?) { |*| Master::Result.ok(true) }
    tool = Master::Io::PluginObserve.new(governor:, event_bus: nil)
    result = tool.call(plugin: "air_superiority", action: "status", args: [])
    refute result.ok?
    assert_equal :validation, result.category
  end
end
