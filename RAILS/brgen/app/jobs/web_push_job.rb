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
      url: target_path(notification),
      tag: "brgen-#{notification.kind}"
    }.to_json

    subscriptions.find_each do |subscription|
      deliver(subscription, payload, vapid)
    end
  end

  private

  # The payload url was hardcoded to "/", so tapping a push about a parcel, an
  # order or a saved-search match landed on the city home page and left the
  # reader to find the thing themselves — which is most of the value of a push
  # gone.
  #
  # Paths are built by hand rather than through url_helpers: a job has no
  # request, so it has no host, and the service worker opens a path anyway.
  # Anything unrecognised still falls back to "/" rather than guessing.
  def target_path(notification)
    id = notification.source_id
    return "/notifications" if id.blank?

    case notification.source_type
    when "Takeaway::Order"    then "/orders/#{id}"
    when "Marketplace::Order" then "/orders/#{id}"
    when "Marketplace::Listing" then "/listings/#{id}"
    when "Marketplace::SavedSearch" then "/saved_searches"
    when "Event"    then "/events/#{id}"
    when "Post"     then "/posts/#{id}"
    when "Message"  then "/conversations"
    when "Community" then "/communities/#{id}"
    else "/notifications"
    end
  end

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
