# frozen_string_literal: true

require "test_helper"
require "minitest/mock"

# The takeaway controllers the engine's own test/ never reached: reviews,
# favourites, menu items, drivers, and the kitchen's status button.
class TakeawayControllersTest < ActionDispatch::IntegrationTest
  setup do
    Brgen::CitySeed.sync! if City.table_exists?
    @city = City.find_by!(domain: "brgen.no")
    ActsAsTenant.current_tenant = @city
    @owner = create_user("tc_owner")
    @diner = create_user("tc_diner")
    @restaurant = Takeaway::Restaurant.create!(
      user: @owner, name: "Kjøkkenet #{SecureRandom.hex(2)}", address: "Torget 2",
      cuisine_type: "Norwegian", city: @city, active: true, min_order_cents: 0
    )
    @soup = Takeaway::MenuItem.create!(restaurant: @restaurant, name: "Fiskesuppe", price_cents: 18_900, available: true)
  end

  teardown do
    ActsAsTenant.current_tenant = nil
  end

  def create_user(name)
    User.strict_loading(false).create!(
      email_address: "#{name}@brgen.no", password: "password123", username: name, guest: false, city: @city
    )
  end

  def sign_in_as(user)
    host! "brgen.no"
    post session_path, params: { email_address: user.email_address, password: "password123" }
    host! "takeaway.brgen.no"
  end

  def delivered_order_for(user)
    place_takeaway_order!(restaurant: @restaurant, user: user, item: @soup).tap { |order| order.update_columns(status: "delivered") }
  end

  test "a review needs a signed-in diner" do
    host! "takeaway.brgen.no"

    assert_no_difference -> { Takeaway::Review.count } do
      post takeaway.restaurant_reviews_path(@restaurant), params: { takeaway_review: { rating: 5, body: "God" } }
    end
    assert_response :redirect
  end

  test "a review needs a delivered order from that kitchen" do
    sign_in_as(@diner)

    assert_no_difference -> { Takeaway::Review.count } do
      post takeaway.restaurant_reviews_path(@restaurant), params: { takeaway_review: { rating: 5, body: "God" } }
    end
    assert_redirected_to takeaway.restaurant_path(@restaurant)
    assert_equal I18n.t("flash.takeaway.review_requires_delivery"), flash[:alert]
  end

  test "a diner whose order arrived can review it once" do
    delivered_order_for(@diner)
    sign_in_as(@diner)

    assert_difference -> { Takeaway::Review.count }, 1 do
      post takeaway.restaurant_reviews_path(@restaurant), params: { takeaway_review: { rating: 4, body: "Varm suppe" } }
    end
    assert_equal I18n.t("flash.takeaway.review_saved"), flash[:notice]

    assert_no_difference -> { Takeaway::Review.count } do
      post takeaway.restaurant_reviews_path(@restaurant), params: { takeaway_review: { rating: 1, body: "Igjen" } }
    end
  end

  test "a restaurant is saved and unsaved" do
    sign_in_as(@diner)

    assert_difference -> { Takeaway::FavoriteRestaurant.where(user_id: @diner.id).count }, 1 do
      post takeaway.restaurant_favorite_restaurant_path(@restaurant)
      post takeaway.restaurant_favorite_restaurant_path(@restaurant)
    end
    assert_equal I18n.t("flash.takeaway.restaurant_saved"), flash[:notice]

    assert_difference -> { Takeaway::FavoriteRestaurant.where(user_id: @diner.id).count }, -1 do
      delete takeaway.restaurant_favorite_restaurant_path(@restaurant)
    end
  end

  test "the owner adds and removes a menu item" do
    sign_in_as(@owner)

    assert_difference -> { @restaurant.menu_items.count }, 1 do
      post takeaway.restaurant_menu_items_path(@restaurant),
           params: { takeaway_menu_item: { name: "Brød", price_cents: 3_000, available: "1" } }
    end
    assert_equal I18n.t("flash.takeaway.menu_item_added"), flash[:notice]

    bread = @restaurant.menu_items.find_by!(name: "Brød")
    assert_difference -> { @restaurant.menu_items.count }, -1 do
      delete takeaway.restaurant_menu_item_path(@restaurant, bread)
    end
  end

  test "an invalid menu item comes back with the reason" do
    sign_in_as(@owner)

    assert_no_difference -> { Takeaway::MenuItem.count } do
      post takeaway.restaurant_menu_items_path(@restaurant), params: { takeaway_menu_item: { name: "Gratis", price_cents: 0 } }
    end
    assert flash[:alert].present?
  end

  test "somebody else's kitchen has no menu to edit" do
    sign_in_as(@diner)

    assert_no_difference -> { Takeaway::MenuItem.count } do
      post takeaway.restaurant_menu_items_path(@restaurant), params: { takeaway_menu_item: { name: "Inntrenger", price_cents: 1_000 } }
    end
    assert_response :not_found
  end

  test "the drivers list names each courier and only the courier edits their row" do
    courier = create_user("tc_courier")
    driver = Takeaway::DeliveryDriver.create!(user: courier, vehicle_type: "bicycle", available: true)
    sign_in_as(@diner)

    get takeaway.delivery_drivers_path
    assert_response :success
    assert_includes response.body, courier.display_name

    patch takeaway.delivery_driver_path(driver), params: { delivery_driver: { vehicle_type: "car" } }
    assert_equal "bicycle", driver.reload.vehicle_type

    sign_in_as(courier)
    patch takeaway.delivery_driver_path(driver), params: { delivery_driver: { vehicle_type: "car" } }
    assert_equal "car", driver.reload.vehicle_type
    assert_equal I18n.t("takeaway.driver_updated"), flash[:notice]
  end

  test "the kitchen cannot skip a step, and is told why" do
    order = place_takeaway_order!(restaurant: @restaurant, user: @diner, item: @soup)
    sign_in_as(@owner)

    patch takeaway.order_path(order), params: { status: "delivered" }

    assert_redirected_to takeaway.order_path(order)
    assert_equal "pending", order.reload.status
    assert flash[:alert].present?
  end

  test "both order forms lock their submit button" do
    sign_in_as(@diner)

    get takeaway.new_restaurant_order_path(@restaurant)
    assert_select "form[data-controller~='form-submit'][data-action*='submit->form-submit#lock']"

    get takeaway.restaurant_path(@restaurant)
    assert_select "form[data-controller~='form-submit'][data-action*='submit->form-submit#lock']"
  end

  test "the restaurant page leads on the delivery fee and lists each dish as a priced tile" do
    sign_in_as(@diner)

    get takeaway.restaurant_path(@restaurant)
    assert_select ".store-breadcrumb a[href=?]", takeaway.restaurants_path(cuisine: "Norwegian")
    assert_select ".store-buybox .store-buybox-price", text: /#{Regexp.escape(@restaurant.delivery_fee_display)}/
    assert_select "#menu .deal-card .deal-price", text: @soup.price_display
    assert_select "#menu .deal-card input.qty-field[name=?]", "takeaway_order[items][#{@soup.id}]"
  end

  # A guest can order, so the kitchen advancing a guest's order notifies a user
  # with no browser subscription that counts. The push must stand down, not 500.
  test "advancing a guest's order sends no push to the guest" do
    host! "takeaway.brgen.no"
    post takeaway.restaurant_orders_path(@restaurant),
         params: { takeaway_order: { delivery_address: "Torget 9", items: { @soup.id => 1 } } }
    order = Takeaway::Order.order(:id).last
    guest = User.find(order.user_id)
    assert guest.guest?, "the order should belong to the guest the request minted"
    PushSubscription.create!(user: guest, endpoint: "https://push.example/guest", p256dh: "p", auth: "a")

    reset!
    sign_in_as(@owner)
    patch takeaway.order_path(order)
    assert_redirected_to takeaway.order_path(order)
    assert_equal "confirmed", order.reload.status

    notification = Notification.where(user_id: guest.id).order(:id).last
    assert notification, "the status change should still record a notification"
    vapid_before = Rails.application.config.x.vapid
    Rails.application.config.x.vapid = { subject: "mailto:a@b.c", public_key: "x", private_key: "y" }
    sent = []
    Webpush.stub(:payload_send, ->(**kw) { sent << kw[:endpoint] }) do
      Shared::WebPushJob.new.perform(notification_id: notification.id)
    end
    assert_empty sent
  ensure
    Rails.application.config.x.vapid = vapid_before
  end
end
