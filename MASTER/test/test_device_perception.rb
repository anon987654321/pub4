# frozen_string_literal: true

require_relative "test_helper"

class TestDevicePerception < Minitest::Test
  def test_sensor_name_discovery_accepts_arrays_and_hashes
    bus = Object.new
    perception = Master::Device::Perception.new(bus:, interval: 1)
    names = perception.send(:discover_sensor_names, ["Accelerometer", "Light"])
    assert_equal ["Accelerometer", "Light"], names
    names = perception.send(:discover_sensor_names, { "Accelerometer" => {}, "Light" => {} })
    assert_equal ["Accelerometer", "Light"], names
  end

  def test_publish_adds_android_source
    events = []
    bus = Object.new
    bus.define_singleton_method(:publish) { |event, payload| events << [event, payload] }
    perception = Master::Device::Perception.new(bus:, interval: 1)
    perception.send(:publish, "device:test", value: 1)
    assert_equal ["device:test", { value: 1, source: "android" }], events.first
  end
end
