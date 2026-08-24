# frozen_string_literal: true

# Relocated from brgen local concerns/ to shared/services to reduce sprawl
# and centralize push notification logic. Used by locations and messages.
module Shared
  module Pushable
    def push_to(user, title:, body: "", url: "/")
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
        sub.destroy
      end
    end

    module_function :push_to
  end
end
