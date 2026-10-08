# frozen_string_literal: true

require_relative "test_helper"

class TestDeviceWakeDefaults < Minitest::Test
  def test_device_wake_does_not_disable_cli_voice
    path = File.expand_path("../bin/device-wake", __dir__)
    source = File.read(path)

    refute_includes source, 'ENV["MASTER_CLI_SPEAK"] = "0"'
    assert_includes source, 'ENV["MASTER_SKIP_TTS"] = "0"'
    assert_includes source, 'ENV["MASTER_CLI_SPEAK"] = "1"'
  end
end
