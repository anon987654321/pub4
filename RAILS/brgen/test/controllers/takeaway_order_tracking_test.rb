# frozen_string_literal: true

require "test_helper"
require "turbo/broadcastable/test_helper"

# The diner's tracking page follows the kitchen: it subscribes to the order,
# each move replaces its status block, and only the current status is read out.
class TakeawayOrderTrackingTest < ActionDispatch::IntegrationTest
  include Turbo::Broadcastable::TestHelper

  setup do
    Brgen::CitySeed.sync! if City.table_exists?
    @city = City.find_by!(domain: "brgen.no")
    ActsAsTenant.current_tenant = @city
    @owner = member("tt_owner")
    @diner = member("tt_diner")
    @restaurant = Takeaway::Restaurant.create!(user: @owner, name: "Sporingskjøkken", address: "Marken 41",
                                               cuisine_type: "Norwegian", city: @city, active: true,
                                               min_order_cents: 0)

    soup = Takeaway::MenuItem.create!(restaurant: @restaurant, name: "Fiskesuppe", price_cents: 18_900, available: true)
    @order = @restaurant.orders.build(user: @diner, delivery_address: "Torget 8")
    @order.order_items.build(menu_item: soup, quantity: 1, unit_price_cents: soup.price_cents)
    @order.save!
  end

  teardown { ActsAsTenant.current_tenant = nil }

  def member(handle)
    User.strict_loading(false).create!(email_address: "#{handle}_#{SecureRandom.hex(3)}@brgen.no",
                                       password: "password123", username: "#{handle}_#{SecureRandom.hex(3)}",
                                       guest: false, city: @city)
  end

  def status_label(status) = I18n.t("takeaway.status_now", status: I18n.t("takeaway.statuses.#{status}"))

  test "the page subscribes to the order and reads out only the current status" do
    host! "brgen.no"
    post session_path, params: { email_address: @diner.email_address, password: "password123" }
    host! "takeaway.brgen.no"

    get takeaway.order_path(@order)

    block = "##{ActionView::RecordIdentifier.dom_id(@order, :status)}"
    assert_select "#{block} > p[role=status]", status_label("pending")
    assert_select "#{block}[aria-live], #{block}[role]", 0
    names = css_select("turbo-cable-stream-source").map { |source| source["signed-stream-name"] }
    assert_includes names, Turbo::StreamsChannel.signed_stream_name(@order)
  end

  test "each move replaces the status block with the new status" do
    streams = capture_turbo_stream_broadcasts(@order) { @order.confirm! }

    replace = streams.sole
    assert_equal "replace", replace["action"]
    assert_equal ActionView::RecordIdentifier.dom_id(@order, :status), replace["target"]
    assert_includes replace.to_html, status_label("confirmed")
  end
end
