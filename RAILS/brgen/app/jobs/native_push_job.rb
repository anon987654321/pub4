# frozen_string_literal: true

# The iOS shell's half of Shared::WebPushJob: the same notification, read off
# the row when the job runs, sent through APNs to the reader's devices.
#
# A chat message is not a Notification row (a thread would flood the
# notifications list), so it used to reach web push only and never a phone.
# It comes in with the reader and the words instead of a row id: user_id:,
# title:, body:, path:, thread:.
class NativePushJob < ApplicationJob
  queue_as :bulk

  discard_on ActiveJob::DeserializationError

  def perform(notification_id = nil, **message)
    return unless Apns.configured?

    message.empty? ? deliver_notification(notification_id) : deliver_message(message)
  end

  private

  def deliver_notification(notification_id)
    notification = ::Notification.strict_loading(false).includes(user: :native_push_tokens).find_by(id: notification_id)
    tokens = notification&.user&.native_push_tokens.to_a
    return if tokens.empty?

    Apns.deliver(tokens, { title: notification.title.presence || "brgen", body: notification.body.to_s,
                           path: notification.push_path, thread: "brgen-#{notification.kind}" })
  end

  # One thread per conversation, so the lock screen stacks a chat's messages
  # under one heading rather than interleaving every conversation.
  def deliver_message(message)
    tokens = NativePushToken.where(user_id: message.fetch(:user_id)).to_a
    return if tokens.empty?

    Apns.deliver(tokens, message.slice(:title, :body, :path, :thread))
  end
end
