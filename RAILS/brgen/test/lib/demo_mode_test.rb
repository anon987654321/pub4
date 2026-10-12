# frozen_string_literal: true

require "test_helper"
require "brgen/demo_mode"

class DemoModeTest < ActiveSupport::TestCase
  test "production seeding requires both explicit demo flags" do
    refute Brgen::DemoMode.seed_allowed?(
      environment: "production",
      env: { "BRGEN_DEMO_MODE" => "1" }
    )
    refute Brgen::DemoMode.seed_allowed?(
      environment: "production",
      env: { "BRGEN_DEMO_NOTICE" => "1" }
    )
    assert Brgen::DemoMode.seed_allowed?(
      environment: "production",
      env: { "BRGEN_DEMO_MODE" => "1", "BRGEN_DEMO_NOTICE" => "1" }
    )
  end

  test "development and tests can seed local demo fixtures without production flags" do
    assert Brgen::DemoMode.seed_allowed?(environment: "development", env: {})
    assert Brgen::DemoMode.seed_allowed?(environment: "test", env: {})
  end
end
