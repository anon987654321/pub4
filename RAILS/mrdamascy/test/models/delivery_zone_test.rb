# frozen_string_literal: true

require "test_helper"

class DeliveryZoneTest < ActiveSupport::TestCase
  test "the min-basket rule is the zone's job to answer" do
    zone = seed_zone!(postcode: "5004", name: "Strandgaten",
                      fee_ore: 2900, min_basket_ore: 15000, eta_minutes: 20)

    assert_not zone.covers?(14999), "just under the minimum must fail"
    assert zone.covers?(15000), "exactly the minimum must pass"
    assert zone.covers?(45000), "a family fest-mezze obviously passes"
  end

  test "zones are found by postcode, whitespace tolerated" do
    zone = seed_zone!(postcode: "5004", name: "Strandgaten")

    assert_equal zone, DeliveryZone.for_postcode("5004")
    assert_equal zone, DeliveryZone.for_postcode(" 5004 ")
    assert_nil DeliveryZone.for_postcode("9999")
    assert_nil DeliveryZone.for_postcode("")
  end

  test "postcodes are unique — one rule per postcode" do
    seed_zone!(postcode: "5004", name: "Strandgaten")
    duplicate = DeliveryZone.new(postcode: "5004", name: "Annet sted",
                                 fee_ore: 3900, min_basket_ore: 20000, eta_minutes: 30)
    assert_not duplicate.valid?, "two zones with the same postcode should be invalid"
  end

  test "zones carry fee, minimum and eta in the expected units" do
    zone = seed_zone!(postcode: "0155", name: "Oslo sentrum",
                      fee_ore: 3900, min_basket_ore: 20000, eta_minutes: 25)

    assert_equal 3900, zone.fee_ore          # øre — 39 kr
    assert_equal 20000, zone.min_basket_ore  # øre — 200 kr
    assert_equal 25, zone.eta_minutes        # minutter
  end
end
