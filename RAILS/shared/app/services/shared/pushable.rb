# frozen_string_literal: true

module Shared
  module Pushable
    # Enqueue, do not send. A slow push service must not make the user's own
    # request slow, so the round trips happen in Shared::WebPushJob.
    def push_to(user, title:, body: "", url: "/")
      return unless Shared::Vapid.configured?
      return unless user.respond_to?(:push_subscriptions)

      Shared::WebPushJob.perform_later(user.id, title:, body:, url:)
    end

    # The actual delivery, called by the job. Named so it is obvious at a call
    # site which one you are reaching for: anything calling deliver_now inside a
    # request is doing the thing this split exists to prevent.
    #
    # config.x.vapid is Shared::Vapid.webpush_options, set once at boot by the
    # shared initializer; reading the config rather than ENV is what lets a test
    # configure push without touching the process environment.
    def deliver_now(user, title:, body: "", url: "/", tag: nil)
      vapid = Rails.application.config.x.vapid
      return if vapid.blank?
      return unless user.respond_to?(:push_subscriptions)
      return if user.respond_to?(:guest?) && user.guest?

      payload = JSON.generate({ title:, body:, url:, tag: }.compact)

      user.push_subscriptions.each do |sub|
        Webpush.payload_send(
          message:  payload,
          endpoint: sub.endpoint,
          p256dh:   sub.p256dh,
          auth:     sub.auth,
          vapid:,
          urgency:  "normal"
        )
      rescue Webpush::ExpiredSubscription, Webpush::InvalidSubscription
        # The endpoint is gone for good; the row is what is wrong, so remove it.
        sub.destroy
      rescue Webpush::Unauthorized => e
        # Not a dead subscription. The gem raises this on 401, 403 and FCM's
        # UnauthorizedRegistration, each of which says our VAPID credentials are
        # wrong, so it fails identically for every row. Destroying on it would
        # unsubscribe every browser on one bad key rotation, and a push
        # subscription cannot be restored from our side. Raised so the failed
        # job is visible.
        Rails.logger&.error("[push] unauthorized — check config.x.vapid, not the subscription: #{e.message.to_s[0, 120]}")
        raise
      rescue StandardError => e
        # A timeout or a 5xx from a push service is that service's bad day, not
        # this subscription's. Left in place, logged, and retried the next time
        # somebody writes to this person.
        Rails.logger&.warn("[push] #{e.class}: #{e.message.to_s[0, 120]}")
      end
    end

    module_function :push_to, :deliver_now
  end
end
