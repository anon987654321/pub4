# frozen_string_literal: true

require "test_helper"

class NotificationsInboxTest < ActionDispatch::IntegrationTest
  setup do
    Brgen::CitySeed.sync! if City.table_exists?
    @city = City.find_by!(domain: "brgen.no")
    ActsAsTenant.current_tenant = @city
    host! "brgen.no"
    @user = User.strict_loading(false).create!(
      email_address: "inbox-#{SecureRandom.hex(3)}@brgen.no",
      password: "password123", username: "inbox_#{SecureRandom.hex(3)}", city: @city
    )
    @actor = User.strict_loading(false).create!(
      email_address: "actor-#{SecureRandom.hex(3)}@brgen.no",
      password: "password123", username: "actor_#{SecureRandom.hex(3)}", city: @city
    )
    post session_path, params: { email_address: @user.email_address, password: "password123" }
  end

  teardown { ActsAsTenant.current_tenant = nil }

  test "follow order and alert kinds render in the inbox" do
    Notification.create!(user: @user, actor: @actor, kind: "follow")
    Notification.create!(user: @user, kind: "order", title: "Paid", body: "ok")
    Notification.create!(user: @user, kind: "alert", title: "Saved search", body: "hit")

    get notifications_path
    assert_response :success
    assert_includes response.body, @actor.display_name
    assert_includes response.body, "Paid"
    assert_includes response.body, "Saved search"
  end

  # update and badge come from Shared::NotificationsController; read_all is
  # brgen's, because its stream re-renders the grouped list.
  test "marking one read, the badge and read_all work through the engine controller" do
    first = Notification.create!(user: @user, actor: @actor, kind: "follow")
    Notification.create!(user: @user, kind: "alert", title: "Saved search", body: "hit")

    patch notification_path(first), as: :turbo_stream
    assert_response :success
    assert first.reload.read_at

    get badge_notifications_path
    assert_equal 1, JSON.parse(response.body).fetch("unread_count")

    patch read_all_notifications_path, as: :turbo_stream
    assert_response :success
    assert_includes response.body, "notification_list"
    assert_equal 0, Notification.where(user: @user, read_at: nil).count
  end

  test "a guest is sent to sign in" do
    delete session_path
    get notifications_path

    assert_response :redirect
  end

  test "a match notification without a stored title does not 500" do
    Notification.create!(user: @user, actor: @actor, kind: "match")

    get notifications_path
    assert_response :success
  end
end
