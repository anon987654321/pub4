# frozen_string_literal: true

require "test_helper"

# What the diner can do with their own takeaway order: give a tip and choose a
# delivery time on the order form, and call the order off while the kitchen
# has not confirmed it.
class TakeawayDinerOrderTest < ActionDispatch::IntegrationTest
  setup do
    Brgen::CitySeed.sync! if City.table_exists?
    @city = City.find_by!(domain: "brgen.no")
    ActsAsTenant.current_tenant = @city
    @owner = create_user("td_owner")
    @diner = create_user("td_diner")
    @restaurant = Takeaway::Restaurant.create!(
      user: @owner, name: "Kjøkkenet #{SecureRandom.hex(2)}", address: "Torget 2",
      cuisine_type: "Norwegian", city: @city, active: true, min_order_cents: 0
    )
    @soup = Takeaway::MenuItem.create!(restaurant: @restaurant, name: "Fiskesuppe", price_cents: 18_900, available: true)
  end

  teardown { ActsAsTenant.current_tenant = nil }

  def create_user(name)
    User.strict_loading(false).create!(
      email_address: "#{name}_#{SecureRandom.hex(2)}@brgen.no", password: "password123",
      username: "#{name}_#{SecureRandom.hex(2)}", guest: false, city: @city
    )
  end

  def sign_in_as(user)
    host! "brgen.no"
    post session_path, params: { email_address: user.email_address, password: "password123" }
    host! "takeaway.brgen.no"
  end

  def page = Nokogiri::HTML(response.body)

  test "the order form offers a tip in kroner and an optional delivery time" do
    sign_in_as(@diner)
    get takeaway.new_restaurant_order_path(@restaurant)

    refute_nil page.at_css("input[name='takeaway_order[delivery_address]']"), "the address is not sent where the controller reads it"
    refute_nil page.at_css("input[name='takeaway_order[tip_kroner]']"), "no tip field"
    refute_nil page.at_css("input[type='datetime-local'][name='takeaway_order[scheduled_for]']"), "no delivery time field"
  end

  test "a tip and a delivery time reach the order and the total" do
    sign_in_as(@diner)
    later = 2.days.from_now.change(hour: 18, min: 0)

    post takeaway.restaurant_orders_path(@restaurant), params: { takeaway_order: {
      delivery_address: "Strandkaien 1", tip_kroner: "30", scheduled_for: later.strftime("%Y-%m-%dT%H:%M"),
      items: { @soup.id => 1 }
    } }

    order = Takeaway::Order.order(:id).last
    assert_redirected_to takeaway.order_path(order)
    assert_equal 3_000, order.tip_cents
    assert_equal later.to_i, order.scheduled_for.to_i
    assert_equal 18_900 + order.delivery_fee_cents.to_i + 3_000, order.total_cents
  end

  test "an empty tip is no tip" do
    sign_in_as(@diner)
    post takeaway.restaurant_orders_path(@restaurant), params: { takeaway_order: {
      delivery_address: "Strandkaien 1", tip_kroner: "", items: { @soup.id => 1 }
    } }

    assert_equal 0, Takeaway::Order.order(:id).last.tip_cents
  end

  test "the diner cancels a pending order and the kitchen is told" do
    order = place_takeaway_order!(restaurant: @restaurant, user: @diner, item: @soup)
    sign_in_as(@diner)
    get takeaway.order_path(order)
    cancel = page.css("form[action='#{takeaway.order_path(order)}']").find { _1.at_css("input[name='status'][value='cancelled']") }
    refute_nil cancel, "a pending order offers the diner no cancel"
    assert_equal I18n.t("takeaway.cancel_order_confirm"), cancel["data-turbo-confirm"]

    patch takeaway.order_path(order), params: { status: "cancelled" }

    assert_redirected_to takeaway.order_path(order)
    assert_equal "cancelled", order.reload.status
    assert Notification.exists?(user_id: @owner.id, source_type: "Takeaway::Order", source_id: order.id,
                                title: I18n.t("takeaway.diner_cancelled_title", id: order.id))
  end

  test "a confirmed order is the kitchen's, and the diner cannot cancel it" do
    order = place_takeaway_order!(restaurant: @restaurant, user: @diner, item: @soup)
    order.confirm!
    sign_in_as(@diner)

    patch takeaway.order_path(order), params: { status: "cancelled" }

    assert_equal "confirmed", order.reload.status
    assert_equal I18n.t("flash.takeaway.cancel_unavailable"), flash[:alert]
  end

  test "the diner cannot move their order any other way" do
    order = place_takeaway_order!(restaurant: @restaurant, user: @diner, item: @soup)
    sign_in_as(@diner)

    patch takeaway.order_path(order), params: { status: "confirmed" }

    assert_equal "pending", order.reload.status
  end
end
