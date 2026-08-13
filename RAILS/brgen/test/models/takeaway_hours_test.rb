# frozen_string_literal: true

require "test_helper"

# Nothing modelled whether a kitchen was open, so a restaurant took orders at
# 04:00 and the customer found out when nobody cooked them. Nothing carried a
# tip, which on a delivery app is most of what a courier earns. And nothing let
# an order be placed for later.
class TakeawayHoursTest < ActiveSupport::TestCase
  setup do
    Brgen::CitySeed.sync! if City.table_exists?
    @city = City.find_by!(domain: "brgen.no")
    ActsAsTenant.current_tenant = @city
    @owner = User.strict_loading(false).create!(
      email_address: "th_owner@brgen.no", password: "password123", city: @city
    )
    @buyer = User.strict_loading(false).create!(
      email_address: "th_buyer@brgen.no", password: "password123", city: @city
    )
    @restaurant = Takeaway::Restaurant.create!(
      user: @owner, name: "Kjokken #{SecureRandom.hex(3)}", address: "Marken 4",
      cuisine_type: "Norwegian", city: @city, active: true, latitude: 60.39, longitude: 5.32
    )
  end

  teardown do
    ActsAsTenant.current_tenant = nil
  end

  def hours(weekday:, opens:, closes:)
    Takeaway::OpeningHour.create!(
      restaurant: @restaurant, weekday: weekday, opens_minute: opens, closes_minute: closes
    )
  end

  # Most restaurants have no hours recorded yet, and defaulting to closed would
  # empty the listing.
  test "a restaurant with no hours recorded counts as open" do
    assert @restaurant.open_now?
  end

  test "open inside the window and shut outside it" do
    monday = Time.zone.local(2026, 8, 10, 12, 0) # a Monday
    hours(weekday: monday.wday, opens: 11 * 60, closes: 22 * 60)

    assert @restaurant.open_now?(monday)
    refute @restaurant.open_now?(monday.change(hour: 9))
    refute @restaurant.open_now?(monday.change(hour: 23))
  end

  # Closing after midnight is normal for a kitchen. Reading only today's row
  # says a place open until 02:00 is shut at 00:30.
  test "a kitchen open past midnight is open just after midnight" do
    saturday = Time.zone.local(2026, 8, 8, 23, 0)
    hours(weekday: saturday.wday, opens: 17 * 60, closes: 26 * 60) # 17:00–02:00

    assert @restaurant.open_now?(saturday)
    assert @restaurant.open_now?(saturday + 90.minutes), "00:30 is still Saturday night to a kitchen"
    refute @restaurant.open_now?(saturday + 4.hours)
  end

  test "an inactive restaurant is shut whatever its hours say" do
    monday = Time.zone.local(2026, 8, 10, 12, 0)
    hours(weekday: monday.wday, opens: 0, closes: 24 * 60)
    @restaurant.update!(active: false)

    refute @restaurant.open_now?(monday)
  end

  # A shut kitchen cannot cook now but can take an order for later.
  test "a closed kitchen still accepts a scheduled order" do
    monday = Time.zone.local(2026, 8, 10, 4, 0)
    hours(weekday: monday.wday, opens: 11 * 60, closes: 22 * 60)

    travel_to monday do
      refute @restaurant.accepting_orders?
      assert @restaurant.accepting_orders?(scheduled_for: 12.hours.from_now)
    end
  end

  test "the tip is part of the total, not added somewhere else later" do
    item = Takeaway::MenuItem.create!(restaurant: @restaurant, name: "Fiskesuppe", price_cents: 18_900, available: true)
    order = Takeaway::Order.create!(
      user: @buyer, restaurant: @restaurant, delivery_address: "Torget 1", tip_cents: 3_000
    )
    order.order_items.create!(menu_item: item, quantity: 1, unit_price_cents: item.price_cents)
    order.calculate_totals!

    assert_equal 18_900 + order.delivery_fee_cents.to_i + 3_000, order.reload.total_cents
  end

  # A scheduled order is not late because it was placed hours ago.
  test "a scheduled order estimates from when it was asked for" do
    later = 6.hours.from_now
    order = Takeaway::Order.create!(
      user: @buyer, restaurant: @restaurant, delivery_address: "Torget 1", scheduled_for: later
    )

    assert order.scheduled?
    assert_in_delta later.to_i, order.estimated_ready_at.to_i, 5

    immediate = Takeaway::Order.create!(
      user: @buyer, restaurant: @restaurant, delivery_address: "Torget 1"
    )
    assert_operator immediate.estimated_ready_at, :<, later
  end

  test "closing before opening is refused" do
    bad = Takeaway::OpeningHour.new(restaurant: @restaurant, weekday: 1, opens_minute: 22 * 60, closes_minute: 11 * 60)

    refute bad.valid?
    assert bad.errors.of_kind?(:closes_minute, :before_open)
  end
end
