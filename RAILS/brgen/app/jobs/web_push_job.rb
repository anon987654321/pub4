# frozen_string_literal: true

# Delivers a Notification to the user's registered browsers via the Web Push
# protocol. Everything upstream already existed (VAPID keys, the webpush gem,
# PushSubscription rows); this is the sender that was missing. Dead endpoints
# (410/404) are pruned as they're discovered. No-ops when VAPID is unconfigured.
class WebPushJob < ApplicationJob
  queue_as :bulk

  def perform(notification_id)
    vapid = Rails.application.config.x.vapid
    return if vapid.blank?

    # Reload with the user preloaded and strict loading off — this runs in a job
    # with no request, where the belongs_to read would otherwise raise.
    notification = ::Notification.strict_loading(false).includes(:user).find_by(id: notification_id)
    return unless notification

    user = notification.user
    return if user.nil? || (user.respond_to?(:guest?) && user.guest?)

    subscriptions = ::PushSubscription.where(user_id: user.id)
    return if subscriptions.empty?

    payload = {
      title: notification.try(:title).presence || "brgen",
      body: notification.try(:body).to_s,
      url: "/",
      tag: "brgen-#{notification.kind}",
    }.to_json

    subscriptions.find_each do |subscription|
      deliver(subscription, payload, vapid)
    end
  end

  private

  def deliver(subscription, payload, vapid)
    Webpush.payload_send(
      message: payload,
      endpoint: subscription.endpoint,
      p256dh: subscription.p256dh,
      auth: subscription.auth,
      vapid: vapid,
      urgency: "normal"
    )
  rescue Webpush::ExpiredSubscription, Webpush::InvalidSubscription, Webpush::Unauthorized
    subscription.destroy
  rescue StandardError => e
    Rails.logger.warn("web push failed: #{e.class}: #{e.message}")
  end
end
