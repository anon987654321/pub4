# frozen_string_literal: true

require "test_helper"

class RegistryTest < ActiveSupport::TestCase
  test "defaults to an isolated simulator" do
    registry = Eritel::Registry.current
    result = registry.check("example.er")

    assert_equal "simulator", result[:source]
    assert_equal true, result[:available]
  end

  test "unknown provider fails closed" do
    Rails.application.config.x.registry_provider = "unknown"
    assert_raises ArgumentError do
      Eritel::Registry.current
    end
  ensure
    Rails.application.config.x.registry_provider = "simulator"
  end
end
