# frozen_string_literal: true

require "test_helper"

# Smoke: partner program models + attribution still work after UI landing.
class PartnerMarketingUiTest < ActiveSupport::TestCase
  test "partner tables and models load" do
    assert defined?(Partner::Program)
    assert defined?(Partner::Membership)
    assert defined?(Partner::Click)
    assert defined?(Partner::Conversion)
    assert defined?(PartnerMarketing)
  end

  test "program commission math stays integer" do
    program = Partner::Program.new(
      name: "Test",
      commission_model: "cpa_percent",
      commission_rate: 1_000, # 10%
      attribution_hours: 720,
      hold_days: 30,
      status: "open"
    )
    assert_equal 250, program.commission_for(2_500)
  end
end
