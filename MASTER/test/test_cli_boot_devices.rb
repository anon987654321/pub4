# frozen_string_literal: true

require_relative "test_helper"

class TestCliBootDevices < Minitest::Test
  Devices = Master::CLI::BootDevices

  PROFILE = <<~TEXT

    Bluetooth Controller:
        State: On
    Connected:
        Some Speaker:
            Minor Type: Speaker
    Not Connected:
        Other Phones:
            Minor Type: Headset
  TEXT

  def test_the_wifi_line_names_power_and_link_but_never_the_network
    line = Devices.net_line(power: "Wi-Fi Power (en0): On", link: "status: active")

    assert_equal "net0 at mainbus0: wifi en0, power on, link up", line
    off = Devices.net_line(power: "Wi-Fi Power (en0): Off", link: "status: inactive")

    assert_equal "net0 at mainbus0: wifi en0, power off, no link", off
  end

  def test_the_bluetooth_line_counts_only_connected_devices
    assert_equal "bth0 at mainbus0: on, 1 connected", Devices.bth_line(PROFILE)
  end

  def test_unreadable_output_prints_nothing
    assert_nil Devices.net_line(power: "", link: "")
    assert_nil Devices.bth_line("")
    assert_nil Devices.bth_line("no controller here")
  end

  def test_the_startup_lines_carry_the_radios_by_default
    assert_equal true, Master.patterns_config.fetch("cli").fetch("boot_devices")
    Devices.stub(:lines, ["net0 at mainbus0: wifi en0, power on, link up"]) do
      splash = Master::Voice::Renderer.new(config: {}).splash("claude-sonnet-5-5")

      assert_includes splash, "net0 at mainbus0"
    end
  end
end
