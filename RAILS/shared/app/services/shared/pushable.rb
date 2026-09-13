# frozen_string_literal: true

module Shared
  module Pushable
    # Enqueue, do not send. This method used to be the send itself — one blocking
    # Webpush.payload_send per subscription, inside whatever controller action
    # called it — so a slow push service made the user's own request slow. Callers
    # keep the same one-line shape; the round trips happen in Shared::WebPushJob.
    def push_to(user, title:, body: "", url: "/")
      return unless Shared::Vapid.configured?
      return unless user.respond_to?(:push_subscriptions)

      Shared::WebPushJob.perform_later(user.id, title:, body:, url:)
    end

    # The actual delivery, called by the jobs. Named so it is obvious at a call
    # site which one you are reaching for: anything calling deliver_now inside a
    # request is doing the thing this split exists to prevent. tag lets a newer
    # push replace an older one of the same kind on the device.
    def deliver_now(user, title:, body: "", url: "/", tag: nil)
      return unless Shared::Vapid.configured?
      return unless user.respond_to?(:push_subscriptions)

      message = JSON.generate({ title:, body:, url:, tag: }.compact)
      user.push_subscriptions.each do |sub|
        Webpush.payload_send(
          message:,
          endpoint: sub.endpoint,
          p256dh:   sub.p256dh,
          auth:     sub.auth,
          vapid:    Shared::Vapid.webpush_options,
          urgency:  "normal",
        )
      rescue Webpush::ExpiredSubscription, Webpush::InvalidSubscription
        # The endpoint is gone for good; the row is what is wrong, so remove it.
        sub.destroy
      rescue Webpush::Unauthorized => e
        # NOT a dead subscription. The gem raises this on 401, 403 and FCM's
        # UnauthorizedRegistration, every one of which says OUR VAPID credentials
        # are wrong, so it fails identically for every row. Destroying on it would
        # unsubscribe every browser on one bad key rotation, and a push
        # subscription cannot be restored from our side. Logging it as a push
        # service's bad day would hide the rotation, so the job fails loudly.
        Rails.logger&.error("[push] unauthorized — check the VAPID keys, not the subscription: #{e.message.to_s[0, 120]}")
        raise
      rescue StandardError => e
        # A timeout or a 5xx from a push service is that service's bad day, not
        # this subscription's. Left in place, logged, and retried the next time
        # somebody writes to this person — rather than destroyed, which would
        # silently unsubscribe people whenever Google had an outage.
        Rails.logger&.warn("[push] #{e.class}: #{e.message.to_s[0, 120]}")
      end
    end

    module_function :push_to, :deliver_now
  end
end
