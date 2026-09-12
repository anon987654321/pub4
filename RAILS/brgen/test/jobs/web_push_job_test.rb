# frozen_string_literal: true

require "test_helper"
require "minitest/mock"

class WebPushJobTest < ActiveSupport::TestCase
  setup do
    Brgen::CitySeed.sync! if City.table_exists?
    @city = City.find_by!(domain: "brgen.no")
    ActsAsTenant.current_tenant = @city
    @user = User.create!(email_address: "wp-#{SecureRandom.hex(4)}@brgen.no", password: "password12345", username: "wp_#{SecureRandom.hex(3)}", city: @city)
    @notification = Notification.create!(user: @user, kind: "follow")
    @vapid_before = Rails.application.config.x.vapid
  end

  teardown do
    Rails.application.config.x.vapid = @vapid_before
    ActsAsTenant.current_tenant = nil
  end

  test "no-ops when VAPID is unconfigured" do
    Rails.application.config.x.vapid = {}
    PushSubscription.create!(user: @user, endpoint: "https://push.example/1", p256dh: "p", auth: "a")
    called = false
    Webpush.stub(:payload_send, ->(**) { called = true }) do
      WebPushJob.new.perform(@notification.id)
    end
    assert_not called
  end

  test "delivers to each subscription when configured" do
    Rails.application.config.x.vapid = { subject: "mailto:a@b.c", public_key: "x", private_key: "y" }
    PushSubscription.create!(user: @user, endpoint: "https://push.example/1", p256dh: "p", auth: "a")
    sent = []
    Webpush.stub(:payload_send, ->(**kw) { sent << kw[:endpoint] }) do
      WebPushJob.new.perform(@notification.id)
    end
    assert_includes sent, "https://push.example/1"
  end

  # Unauthorized is 401/403 — our VAPID keys, not this reader's browser. It
  # fails the same way for every row, so destroying on it unsubscribes the whole
  # city on one bad rotation, and nothing on our side can put those rows back.
  test "keeps the subscription when the push service rejects our credentials" do
    Rails.application.config.x.vapid = { subject: "mailto:a@b.c", public_key: "x", private_key: "y" }
    sub = PushSubscription.create!(user: @user, endpoint: "https://push.example/live", p256dh: "p", auth: "a")
    Webpush.stub(:payload_send, ->(**) { raise Webpush::Unauthorized.allocate }) do
      assert_raises(Webpush::Unauthorized) { WebPushJob.new.perform(@notification.id) }
    end
    assert PushSubscription.exists?(sub.id)
  end

  test "prunes a subscription the push service has expired" do
    Rails.application.config.x.vapid = { subject: "mailto:a@b.c", public_key: "x", private_key: "y" }
    sub = PushSubscription.create!(user: @user, endpoint: "https://push.example/gone", p256dh: "p", auth: "a")
    Webpush.stub(:payload_send, ->(**) { raise Webpush::ExpiredSubscription.allocate }) do
      WebPushJob.new.perform(@notification.id)
    end
    assert_not PushSubscription.exists?(sub.id)
  end
end
