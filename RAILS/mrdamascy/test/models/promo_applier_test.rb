# frozen_string_literal: true

require "test_helper"

class PromoApplierTest < ActiveSupport::TestCase
  setup do
    @user = seed_customer!(name: "Ola Nordmann")
  end

  # Single adapter point for the PromoApplier contract (APP_SPEC §5):
  # call with the cart subtotal, the current delivery fee, the mode and the
  # (optional) user — get back { promo:, discount_ore:, delivery_fee_ore: }.
  def apply(subtotal_ore:, delivery_fee_ore: 2900, mode: "delivery", user: nil)
    PromoApplier.call(subtotal_ore: subtotal_ore, delivery_fee_ore: delivery_fee_ore,
                      delivery_mode: mode, user: user)
  end

  test "percent beats fixed and free delivery at a mid-size basket" do
    seed_promo!(code: "SAHTEIN10", kind: "percent", value: 10)
    seed_promo!(code: "YALLA25", kind: "fixed", value: 2500, min_basket_ore: 25000)
    seed_promo!(code: "GRATISLEVERING", kind: "free_delivery", value: 0, min_basket_ore: 30000)

    result = apply(subtotal_ore: 30000, delivery_fee_ore: 2900)

    # SAHTEIN10 saves 3 000 — more than YALLA25 (2 500) and GRATISLEVERING (2 900).
    assert_equal "SAHTEIN10", result[:promo].code
    assert_equal 3000, result[:discount_ore]
    assert_equal 2900, result[:delivery_fee_ore]
  end

  test "free delivery wins when its saving is the biggest and zeroes the fee" do
    seed_promo!(code: "SAHTEIN10", kind: "percent", value: 10)
    seed_promo!(code: "GRATISLEVERING", kind: "free_delivery", value: 0, min_basket_ore: 30000)

    result = apply(subtotal_ore: 31000, delivery_fee_ore: 4500)

    # 4 500 fee beats 3 100 of percent discount.
    assert_equal "GRATISLEVERING", result[:promo].code
    assert_equal 0, result[:delivery_fee_ore]
    assert_equal 0, result[:discount_ore], "free delivery zeroes the fee, not the basket"
  end

  test "family percent wins on big family baskets" do
    seed_promo!(code: "SAHTEIN10", kind: "percent", value: 10)
    seed_promo!(code: "FAMILIE15", kind: "percent", value: 15, min_basket_ore: 40000)

    result = apply(subtotal_ore: 60000, delivery_fee_ore: 4500)

    assert_equal "FAMILIE15", result[:promo].code
    assert_equal 9000, result[:discount_ore]
    assert_equal 4500, result[:delivery_fee_ore]
  end

  test "pickup mode skips free-delivery promos since there is no fee" do
    seed_promo!(code: "SAHTEIN10", kind: "percent", value: 10)
    seed_promo!(code: "GRATISLEVERING", kind: "free_delivery", value: 0, min_basket_ore: 30000)

    result = apply(subtotal_ore: 31000, delivery_fee_ore: 4500, mode: "pickup")

    assert_equal "SAHTEIN10", result[:promo].code
    assert_equal 3100, result[:discount_ore]
    assert_equal 0, result[:delivery_fee_ore]
  end

  test "no qualifying promo returns nothing" do
    seed_promo!(code: "FAMILIE15", kind: "percent", value: 15, min_basket_ore: 40000)

    result = apply(subtotal_ore: 10000, delivery_fee_ore: 2900)

    assert_nil result[:promo]
    assert_equal 0, result[:discount_ore]
    assert_equal 2900, result[:delivery_fee_ore]
  end

  test "inactive promos are never picked" do
    seed_promo!(code: "SAHTEIN10", kind: "percent", value: 10, active: false)

    result = apply(subtotal_ore: 30000)

    assert_nil result[:promo]
    assert_equal 0, result[:discount_ore]
  end

  test "the tenth stamp makes the cheapest wrap free" do
    kitchen = seed_kitchen!
    wraps = seed_category!(kitchen, slug: "wraps")
    seed_item!(wraps, name: "Damaskus Kylling Shawarma", price_ore: 12900)
    seed_item!(wraps, name: "Beirut Lam Shawarma", name_en: "Beirut Lamb Shawarma",
               price_ore: 13900)

    9.times { LoyaltyStamp.create!(user: @user, redeemed: false, awarded_at: Time.current) }

    result = apply(subtotal_ore: 20000, user: @user)

    assert_equal 12900, result[:discount_ore], "the cheapest wrap should be free"
  end

  test "fewer than nine unredeemed stamps give no free wrap" do
    kitchen = seed_kitchen!
    wraps = seed_category!(kitchen, slug: "wraps")
    seed_item!(wraps, name: "Damaskus Kylling Shawarma", price_ore: 12900)

    8.times { LoyaltyStamp.create!(user: @user, redeemed: false, awarded_at: Time.current) }

    result = apply(subtotal_ore: 20000, user: @user)

    assert_equal 0, result[:discount_ore]
  end

  test "redeemed stamps do not count toward the free wrap" do
    kitchen = seed_kitchen!
    wraps = seed_category!(kitchen, slug: "wraps")
    seed_item!(wraps, name: "Damaskus Kylling Shawarma", price_ore: 12900)

    9.times { LoyaltyStamp.create!(user: @user, redeemed: true, awarded_at: 1.month.ago) }

    result = apply(subtotal_ore: 20000, user: @user)

    assert_equal 0, result[:discount_ore]
  end
end
