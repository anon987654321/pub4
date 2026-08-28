# frozen_string_literal: true

require "test_helper"

# Two faults on the same path, which is why nothing time-critical ever reached a
# lock screen or read correctly in the list.
#
# Shared::Notifiable dropped `kind` on its title/body branch, so every
# transactional notification — an order advancing, a saved search matching, a
# listing about to lapse — was written as the column default "custom", which is
# not in PUSHABLE_KINDS. And Notification#title/#body were methods shadowing the
# real columns, so the stored title rendered as "New notification" with an empty
# body in the list, the row partial and the push payload.
class NotificationPushTest < ActiveSupport::TestCase
  setup do
    Brgen::CitySeed.sync! if City.table_exists?
    @city = City.find_by!(domain: "brgen.no")
    ActsAsTenant.current_tenant = @city
    @user = User.strict_loading(false).create!(
      email_address: "np_user@brgen.no", password: "password123", username: "np_user", city: @city
    )
    @seller = User.strict_loading(false).create!(
      email_address: "np_seller@brgen.no", password: "password123", username: "np_seller", city: @city
    )
    @category = Marketplace::Category.create!(name: "Diverse-#{SecureRandom.hex(3)}")
  end

  teardown do
    ActsAsTenant.current_tenant = nil
  end

  test "a kind passed with title and body is kept, not silently defaulted" do
    Marketplace::Order.deliver_notification(
      @user, title: "Order paid", body: "It cleared", kind: "order"
    )

    assert_equal "order", @user.notifications.last.kind
  end

  test "the stored title and body win over the derived sentence" do
    Marketplace::Order.deliver_notification(
      @user, title: "On its way", body: "Posten: NO123", kind: "order"
    )
    notification = @user.notifications.last

    assert_equal "On its way", notification.title
    assert_equal "Posten: NO123", notification.body
  end

  # The structured social kinds store neither, so they still derive.
  test "a kind with no stored title still derives its sentence" do
    notification = @user.notifications.create!(kind: "follow", actor: @seller)

    assert_equal I18n.t("notifications.sentences.follow", name: @seller.display_name), notification.title
  end

  test "order and alert are pushable, and a bare custom notification is not" do
    assert_includes Notification::PUSHABLE_KINDS, "order"
    assert_includes Notification::PUSHABLE_KINDS, "alert"
    refute_includes Notification::PUSHABLE_KINDS, "custom"
    refute_includes Notification::PUSHABLE_KINDS, "like"
  end

  test "a takeaway status change is written as a pushable order notification" do
    owner = User.strict_loading(false).create!(
      email_address: "np_owner@brgen.no", password: "password123", city: @city
    )
    restaurant = Takeaway::Restaurant.create!(
      user: owner, name: "Kjokken #{SecureRandom.hex(3)}", address: "Marken 4",
      cuisine_type: "Norwegian", city: @city, active: true
    )
    order = place_takeaway_order!(user: @user, restaurant: restaurant)

    order.confirm!
    assert_equal "order", @user.notifications.last.kind
  end

  test "a saved-search match is written as a pushable alert" do
    search = @user.marketplace_saved_searches.create!(query: "sykkel", notify: true)
    Marketplace::Listing.create!(
      user: @seller, title: "Terrengsykkel", category: @category,
      price_cents: 50_000, status: "active"
    )

    SavedSearchAlertJob.perform_now
    assert_equal "alert", @user.notifications.last.kind
    assert_not_nil search.reload.last_notified_at
  end

  test "a listing expiry warning is written as a pushable alert" do
    listing = Marketplace::Listing.create!(
      user: @user, title: "Utloper", category: @category, price_cents: 1_000, status: "active"
    )
    listing.update_columns(expires_at: 3.days.from_now)

    ListingExpiryJob.perform_now
    assert_equal "alert", @user.notifications.last.kind
  end

  # The payload url was hardcoded to "/", so tapping a push about a parcel
  # landed on the city home page and left the reader to find it themselves.
  test "the push payload points at the thing it is about" do
    job = WebPushJob.new
    path = job.send(:target_path, Notification.new(source_type: "Takeaway::Order", source_id: 42))
    assert_equal "/orders/42", path

    assert_equal "/events/7", job.send(:target_path, Notification.new(source_type: "Event", source_id: 7))
    assert_equal "/saved_searches",
                 job.send(:target_path, Notification.new(source_type: "Marketplace::SavedSearch", source_id: 3))
  end

  test "an unknown or absent source falls back rather than guessing" do
    job = WebPushJob.new

    assert_equal "/notifications", job.send(:target_path, Notification.new(source_type: "Whatever", source_id: 1))
    assert_equal "/notifications", job.send(:target_path, Notification.new(source_type: "Post", source_id: nil))
  end
end
