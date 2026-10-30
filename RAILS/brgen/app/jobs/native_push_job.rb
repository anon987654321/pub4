# frozen_string_literal: true

# The iOS shell's half of Shared::WebPushJob: the same notification, read off
# the row when the job runs, sent through APNs to the reader's devices.
class NativePushJob < ApplicationJob
  queue_as :bulk

  discard_on ActiveJob::DeserializationError

  def perform(notification_id)
    return unless Apns.configured?

    notification = ::Notification.strict_loading(false).includes(user: :native_push_tokens).find_by(id: notification_id)
    tokens = notification&.user&.native_push_tokens.to_a
    return if tokens.empty?

    Apns.deliver(tokens, { title: notification.title.presence || "brgen", body: notification.body.to_s,
                           path: notification.push_path, thread: "brgen-#{notification.kind}" })
  end
end
