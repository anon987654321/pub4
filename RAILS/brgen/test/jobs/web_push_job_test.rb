# frozen_string_literal: true

require "test_helper"
require "minitest/mock"

# WebPushJob builds brgen's payload and hands delivery to Shared::Pushable, which
# reads the VAPID keys from the environment through Shared::Vapid.
class WebPushJobTest < ActiveSupport::TestCase
  VAPID_KEYS = %w[VAPID_PUBLIC_KEY VAPID_PRIVATE_KEY].freeze

  setup do
    Brgen::CitySeed.sync! if City.table_exists?
    @city = City.find_by!(domain: "brgen.no")
    ActsAsTenant.current_tenant = @city
    @user = User.create!(email_address: "wp-#{SecureRandom.hex(4)}@brgen.no", password: "password12345", username: "wp_#{SecureRandom.hex(3)}", city: @city)
    @notification = Notification.create!(user: @user, kind: "follow")
    @env_before = VAPID_KEYS.to_h { |key| [ key, ENV[key] ] }
    VAPID_KEYS.each { |key| ENV[key] = "test-#{key.downcase}" }
  end

  teardown do
    @env_before.each { |key, value| value.nil? ? ENV.delete(key) : ENV[key] = value }
    ActsAsTenant.current_tenant = nil
  end

  test "no-ops when VAPID is unconfigured" do
    VAPID_KEYS.each { |key| ENV.delete(key) }
    PushSubscription.create!(user: @user, endpoint: "https://push.example/1", p256dh: "p", auth: "a")
    called = false
    Webpush.stub(:payload_send, ->(**) { called = true }) do
      WebPushJob.new.perform(@notification.id)
    end
    assert_not called
  end

  test "delivers brgen's payload to each subscription when configured" do
    PushSubscription.create!(user: @user, endpoint: "https://push.example/1", p256dh: "p", auth: "a")
    sent = []
    Webpush.stub(:payload_send, ->(**kw) { sent << kw }) do
      WebPushJob.new.perform(@notification.id)
    end

    assert_equal [ "https://push.example/1" ], sent.map { |kw| kw[:endpoint] }
    payload = JSON.parse(sent.first[:message])
    assert_equal "brgen-follow", payload["tag"]
    assert_equal "/notifications", payload["url"]
  end

  # Unauthorized is 401/403 — our VAPID keys, not this reader's browser. It
  # fails the same way for every row, so destroying on it unsubscribes the whole
  # city on one bad rotation, and nothing on our side can put those rows back.
  test "keeps the subscription when the push service rejects our credentials" do
    sub = PushSubscription.create!(user: @user, endpoint: "https://push.example/live", p256dh: "p", auth: "a")
    Webpush.stub(:payload_send, ->(**) { raise Webpush::Unauthorized.allocate }) do
      assert_raises(Webpush::Unauthorized) { WebPushJob.new.perform(@notification.id) }
    end
    assert PushSubscription.exists?(sub.id)
  end

  test "prunes a subscription the push service has expired" do
    sub = PushSubscription.create!(user: @user, endpoint: "https://push.example/gone", p256dh: "p", auth: "a")
    Webpush.stub(:payload_send, ->(**) { raise Webpush::ExpiredSubscription.allocate }) do
      WebPushJob.new.perform(@notification.id)
    end
    assert_not PushSubscription.exists?(sub.id)
  end
end
