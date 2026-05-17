module Pushable
  VAPID = {
    subject:     -> { "mailto:#{ENV.fetch("VAPID_SUBJECT", "admin@brgen.no")}" },
    public_key:  -> { ENV.fetch("VAPID_PUBLIC_KEY",  "") },
    private_key: -> { ENV.fetch("VAPID_PRIVATE_KEY", "") }
  }.freeze

  def push_to(user, title:, body: "", url: "/")
    return if VAPID[:public_key].call.empty?

    user.push_subscriptions.each do |sub|
      Webpush.payload_send(
        message:  JSON.generate({ title:, body:, url: }),
        endpoint: sub.endpoint,
        p256dh:   sub.p256dh,
        auth:     sub.auth,
        vapid:    { subject: VAPID[:subject].call, public_key: VAPID[:public_key].call, private_key: VAPID[:private_key].call }
      )
    rescue Webpush::ExpiredSubscription, Webpush::InvalidSubscription
      sub.destroy
    end
  end

  module_function :push_to
end
