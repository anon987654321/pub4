# frozen_string_literal: true

require_relative "test_helper"

class TestDevice < Minitest::Test
  Device = Master::Device

  def test_non_android_reports_unavailable_without_touching_hardware
    stub_const = RbConfig::CONFIG["host_os"]
    RbConfig::CONFIG["host_os"] = "darwin"
    ENV.delete("TERMUX_VERSION")
    ENV.delete("PREFIX")
    refute Device.android?
    assert_equal :unavailable, Device.capabilities.first.state
  ensure
    RbConfig::CONFIG["host_os"] = stub_const
  end

  def test_android_is_detected_from_termux_environment
    stub_const = RbConfig::CONFIG["host_os"]
    RbConfig::CONFIG["host_os"] = "linux-android"
    ENV["PREFIX"] = "/data/data/com.termux/files/usr"
    assert Device.android?
  ensure
    RbConfig::CONFIG["host_os"] = stub_const
    ENV.delete("PREFIX")
  end

  def test_termux_detection_uses_client_commands_not_helper_binary
    stub_const = RbConfig::CONFIG["host_os"]
    RbConfig::CONFIG["host_os"] = "linux-android"
    ENV["PREFIX"] = "/data/data/com.termux/files/usr"
    Dir.mktmpdir do |dir|
      path = File.join(dir, "termux-battery-status")
      File.write(path, "#!/bin/sh\n")
      File.chmod(0o755, path)
      old_path = ENV["PATH"]
      ENV["PATH"] = dir
      assert Device.termux?
    ensure
      ENV["PATH"] = old_path
    end
  ensure
    RbConfig::CONFIG["host_os"] = stub_const
    ENV.delete("PREFIX")
  end

  def test_missing_api_is_truthful
    stub_const = RbConfig::CONFIG["host_os"]
    RbConfig::CONFIG["host_os"] = "linux-android"
    ENV["PREFIX"] = "/data/data/com.termux/files/usr"
    refute Device.termux?
    assert Device.capabilities.all? { |cap| cap.state == :unavailable }
  ensure
    RbConfig::CONFIG["host_os"] = stub_const
    ENV.delete("PREFIX")
  end

  def test_status_is_dmesg_style
    lines = Device.status_lines
    assert lines.first.start_with?("device0:")
    refute lines.any? { |line| line.include?("|") || line.include?("·") }
  end
end
