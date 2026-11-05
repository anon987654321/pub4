# frozen_string_literal: true

require "application_system_test_case"

# The takeaway order form says how far the chosen food is from the kitchen's
# minimum as the diner changes quantities, before the server's below_minimum
# error would.
class TakeawayOrderTotalTest < ApplicationSystemTestCase
  include CityHostSystemTest

  setup do
    Brgen::CitySeed.sync! if City.table_exists? && !City.exists?(domain: "brgen.no")
    @city = City.find_by!(domain: "brgen.no")
    @diner = User.strict_loading(false).create!(
      email_address: "tt_diner_#{SecureRandom.hex(2)}@brgen.no", password: "password123",
      username: "tt_diner_#{SecureRandom.hex(2)}", guest: false, city: @city
    )
    owner = User.strict_loading(false).create!(
      email_address: "tt_owner_#{SecureRandom.hex(2)}@brgen.no", password: "password123",
      username: "tt_owner_#{SecureRandom.hex(2)}", guest: false, city: @city
    )
    ActsAsTenant.with_tenant(@city) do
      @restaurant = Takeaway::Restaurant.create!(
        user: owner, name: "Suppekjøkkenet #{SecureRandom.hex(2)}", address: "Torget 2",
        cuisine_type: "Norwegian", city: @city, active: true, min_order_cents: 25_000
      )
      @soup = Takeaway::MenuItem.create!(restaurant: @restaurant, name: "Fiskesuppe", price_cents: 18_900, available: true)
    end
  end

  def folded(text) = text.gsub(/[[:space:]]/, " ")

  test "the subtotal and the distance to the minimum follow the quantities" do
    sign_in_on_city(@diner)
    visit_city("takeaway", "/restaurants/#{@restaurant.to_param}/orders/new")

    shortfall = ->(cents) { folded(I18n.t("takeaway.minimum_shortfall", amount: Shared::MoneyDisplay.format(cents))) }
    subtotal = ->(cents) { folded(I18n.t("takeaway.subtotal", amount: Shared::MoneyDisplay.format(cents))) }
    line = -> { folded(find(".order-running-total").text) }

    assert_includes line.call, shortfall.call(25_000)

    fill_in "takeaway_order_items_#{@soup.id}", with: "1"
    assert wait_until { line.call.include?(shortfall.call(6_100)) }, "the shortfall did not follow one soup: #{line.call}"
    assert_includes line.call, subtotal.call(18_900)

    fill_in "takeaway_order_items_#{@soup.id}", with: "2"
    assert wait_until { line.call.include?(I18n.t("takeaway.minimum_reached")) }, "the minimum was not reached at two: #{line.call}"
    assert_includes line.call, subtotal.call(37_800)
  end
end
