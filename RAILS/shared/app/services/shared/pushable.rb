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

    # The actual delivery, called by the job. Named so it is obvious at a call
    # site which one you are reaching for: anything calling deliver_now inside a
    # request is doing the thing this split exists to prevent.
    def deliver_now(user, title:, body: "", url: "/")
      return unless Shared::Vapid.configured?
      return unless user.respond_to?(:push_subscriptions)

      user.push_subscriptions.each do |sub|
        Webpush.payload_send(
          message:  JSON.generate({ title:, body:, url: }),
          endpoint: sub.endpoint,
          p256dh:   sub.p256dh,
          auth:     sub.auth,
          vapid:    Shared::Vapid.webpush_options,
        )
      rescue Webpush::ExpiredSubscription, Webpush::InvalidSubscription
        # The endpoint is gone for good; the row is what is wrong, so remove it.
        sub.destroy
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
