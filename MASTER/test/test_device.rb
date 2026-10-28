# frozen_string_literal: true

require_relative "test_helper"

class TestDevice < Minitest::Test
  Device = Master::Device

  # Every case here rewrites the host and Termux environment; each one gets the
  # process's own values back, so a later test does not run on a phantom phone.
  def setup
    @saved_env = ENV.to_h.slice("TERMUX_VERSION", "PREFIX", "PATH")
    @saved_host = RbConfig::CONFIG["host_os"]
  end

  def teardown
    %w[TERMUX_VERSION PREFIX].each { |key| ENV.delete(key) }
    @saved_env.each { |key, value| ENV[key] = value }
    RbConfig::CONFIG["host_os"] = @saved_host
  end

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

  def test_android_audio_commands_are_part_of_capability_discovery
    assert_equal "termux-tts-speak", Device::API_COMMANDS.fetch(:tts)
    assert_equal "termux-media-player", Device::API_COMMANDS.fetch(:media_player)
  end

  def test_android_commands_use_the_bounded_exec_primitive
    stub_const = RbConfig::CONFIG["host_os"]
    RbConfig::CONFIG["host_os"] = "linux-android"
    ENV["PREFIX"] = "/data/data/com.termux/files/usr"

    status = Object.new
    def status.success? = true

    Master::Device.stub(:executable?, true) do
      Master::Io::Exec.stub(:capture3, ["ok\n", "", status]) do
        # This proves the runtime reaches the sanctioned subprocess primitive.
        assert_equal "ok", Device.send(:run!, "termux-battery-status")
      end
    end
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
