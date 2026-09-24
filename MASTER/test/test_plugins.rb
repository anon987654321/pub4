<sub># frozen_string_literal: true

require_relative "test_helper"

class PluginsTest < Minitest::Test
  def setup
    @plugins_root = File.join(Master::ROOT, "plugins")
  end

  def test_registry_discovers_built_in_plugins
    ids = Master::Plugin.list.map(&:id)
    assert_equal %w[air_superiority social_browser], ids
  end

  def test_manifest_entries_are_constrained_and_versioned
    Master::Plugin.list.each do |manifest|
      assert_match(/\A[a-z][a-z0-9_]*\z/, manifest.id)
      assert_match(/\A\d+\.\d+\.\d+\z/, manifest.version)
      assert File.file?(manifest.path)
    end
  end

  def test_plugin_classes_load_through_manifest_entrypoints
    assert_instance_of Master::Plugins::AirSuperiority, Master::Plugin.load("air_superiority")
    assert_instance_of Master::Plugins::SocialBrowser, Master::Plugin.load("social_browser")
  end

  def test_social_browser_policy_rejects_unsolicited_bulk_style_action
    error = assert_raises(Master::Plugin::PolicyError) do
      Master::Plugin.run(
        "social_browser",
        action: "reply_inbound",
        account: "brand",
        conversation_url: "https://example.test/inbox/1",
        message: "hello",
        allowed_hosts: ["example.test"],
        consent: true,
        inbound: false
      )
    end
    assert_match(/inbound=true/, error.message)
  end

  def test_social_browser_requires_explicit_target_host
    plugin = Master::Plugin.load("social_browser")
    error = assert_raises(Master::Plugin::PolicyError) do
      plugin.send(
        :validate_url!,
        "https://social.example/profile",
        []
      )
    end
    assert_match(/allowed_hosts/, error.message)
  end

  def test_air_superiority_wifi_parser_and_threat_logic
    plugin = Master::Plugin.load("air_superiority")
    networks = plugin.send(
      :parse_openbsd_scan,
      'nwid "Home" chan 44 bssid aa:bb:cc:dd:ee:ff rssi -52',
      root: nil
    )
    assert_equal 1, networks.length
    assert_equal "Home", networks.first[:ssid]
    assert_equal "aa:bb:cc:dd:ee:ff", networks.first[:bssid]

    threats = plugin.send(
      :analyze_wifi,
      [
        { ssid: "Home", bssid: "11:22:33:44:55:66", security: "WPA2", rssi: -51 }
      ],
      [{ "ssid" => "Home", "bssid" => "aa:bb:cc:dd:ee:ff" }]
    )
    assert_equal "Unexpected Access Point", threats.first.type
    assert_equal "high", threats.first.severity
  end

  def test_air_superiority_bluetooth_threat_logic_is_local
    plugin = Master::Plugin.load("air_superiority")
    threats = plugin.send(
      :analyze_bluetooth,
      [{ name: "headphones", address: "AA:BB:CC:DD:EE:FF" }],
      []
    )
    assert_equal "Unknown Bluetooth Device", threats.first.type
    assert_equal "low", threats.first.severity
  end
end
</sub>