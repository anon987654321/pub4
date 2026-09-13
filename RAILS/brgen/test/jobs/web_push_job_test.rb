# frozen_string_literal: true

require "test_helper"
require "minitest/mock"

class WebPushJobTest < ActiveSupport::TestCase
  include ActiveJob::TestHelper

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
      Shared::WebPushJob.new.perform(notification_id: @notification.id)
    end
    assert_not called
  end

  test "delivers to each subscription when configured" do
    Rails.application.config.x.vapid = { subject: "mailto:a@b.c", public_key: "x", private_key: "y" }
    PushSubscription.create!(user: @user, endpoint: "https://push.example/1", p256dh: "p", auth: "a")
    sent = []
    Webpush.stub(:payload_send, ->(**kw) { sent << kw[:endpoint] }) do
      Shared::WebPushJob.new.perform(notification_id: @notification.id)
    end
    assert_includes sent, "https://push.example/1"
  end

  test "the notification path carries its title, deep link and tag" do
    Rails.application.config.x.vapid = { subject: "mailto:a@b.c", public_key: "x", private_key: "y" }
    PushSubscription.create!(user: @user, endpoint: "https://push.example/1", p256dh: "p", auth: "a")
    messages = []
    Webpush.stub(:payload_send, ->(**kw) { messages << JSON.parse(kw[:message]) }) do
      Shared::WebPushJob.new.perform(notification_id: @notification.id)
    end
    assert_equal "/notifications", messages.first["url"]
    assert_equal "brgen-follow", messages.first["tag"]
    assert_equal @notification.title, messages.first["title"]
  end

  test "the user and payload path delivers what Shared::Pushable enqueued" do
    Rails.application.config.x.vapid = { subject: "mailto:a@b.c", public_key: "x", private_key: "y" }
    PushSubscription.create!(user: @user, endpoint: "https://push.example/2", p256dh: "p", auth: "a")
    messages = []
    Webpush.stub(:payload_send, ->(**kw) { messages << JSON.parse(kw[:message]) }) do
      Shared::WebPushJob.new.perform(@user.id, title: "t", body: "b", url: "/conversations")
    end
    assert_equal({ "title" => "t", "body" => "b", "url" => "/conversations" }, messages.first)
  end

  test "a pushable notification enqueues the shared job by notification id" do
    notification = nil
    assert_enqueued_jobs 1, only: Shared::WebPushJob do
      notification = Notification.create!(user: @user, kind: "follow")
    end
    assert_equal [ { "notification_id" => notification.id, "_aj_ruby2_keywords" => [ "notification_id" ] } ],
                 enqueued_jobs.last["arguments"]
  end

  # Unauthorized is 401/403 — our VAPID keys, not this reader's browser. It
  # fails the same way for every row, so destroying on it unsubscribes the whole
  # city on one bad rotation, and nothing on our side can put those rows back.
  test "keeps the subscription when the push service rejects our credentials" do
    Rails.application.config.x.vapid = { subject: "mailto:a@b.c", public_key: "x", private_key: "y" }
    sub = PushSubscription.create!(user: @user, endpoint: "https://push.example/live", p256dh: "p", auth: "a")
    Webpush.stub(:payload_send, ->(**) { raise Webpush::Unauthorized.allocate }) do
      assert_raises(Webpush::Unauthorized) { Shared::WebPushJob.new.perform(notification_id: @notification.id) }
    end
    assert PushSubscription.exists?(sub.id)
  end

  test "prunes a subscription the push service has expired" do
    Rails.application.config.x.vapid = { subject: "mailto:a@b.c", public_key: "x", private_key: "y" }
    sub = PushSubscription.create!(user: @user, endpoint: "https://push.example/gone", p256dh: "p", auth: "a")
    Webpush.stub(:payload_send, ->(**) { raise Webpush::ExpiredSubscription.allocate }) do
      Shared::WebPushJob.new.perform(notification_id: @notification.id)
    end
    assert_not PushSubscription.exists?(sub.id)
  end
end
