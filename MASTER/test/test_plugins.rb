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
        owned_account: false
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
end
