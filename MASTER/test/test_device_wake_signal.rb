# frozen_string_literal: true

require "minitest/autorun"
require "tmpdir"
require_relative "../lib/device/wake_signal"

class TestDeviceWakeSignal < Minitest::Test
  def test_publish_is_atomic_and_readable
    Dir.mktmpdir do |root|
      event = Master::Device::WakeSignal.publish(root:, phrase: "hey mochi", at: 123.45)

      assert_equal 1, event[:version]
      assert_equal "device:wake", event[:type]
      assert_equal "hey mochi", event[:phrase]
      assert_equal 123.45, event[:at]
      assert_equal event[:id], Master::Device::WakeSignal.read(root:)[:id]
      assert_empty Dir.children(File.join(root, ".master")).grep(/wake-event-/)
    end
  end

  def test_missing_signal_is_empty
    Dir.mktmpdir do |root|
      assert_nil Master::Device::WakeSignal.read(root:)
    end
  end
end
