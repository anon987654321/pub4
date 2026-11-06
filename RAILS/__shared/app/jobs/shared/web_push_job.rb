# frozen_string_literal: true

module Shared
  # Web push, off the request.
  #
  # push_to sent inline: one blocking HTTP POST per subscription per recipient,
  # inside the controller action. Sending a message to a room with twenty people
  # on two devices each meant forty round trips to Google and Mozilla before the
  # sender saw their own message — on one vCPU, behind Falcon, where that request
  # is holding a thread the whole time. A push service being slow made *sending*
  # slow, which is the wrong thing to couple.
  #
  # :bulk rather than :critical. A notification arriving a second late is not a
  # failure; a message failing to send because a push endpoint timed out is.
  #
  # Two call shapes, one sender. Shared::Pushable passes a user id and the
  # payload; a Notification passes only its own id, and the payload is read off
  # the row when the job runs, so an edit between enqueue and delivery is what
  # the lock screen shows.
  class WebPushJob < ApplicationJob
    queue_as :bulk

    # discard rather than retry: the payload names a message that has already been
    # delivered over Turbo. A retry storm to a dead endpoint helps nobody, and the
    # subscription cleanup in Shared::Pushable is what actually fixes the cause.
    discard_on ActiveJob::DeserializationError

    def perform(user_id = nil, title: nil, body: "", url: "/", notification_id: nil)
      return deliver_notification(notification_id) if notification_id

      user = User.find_by(id: user_id)
      return unless user

      Shared::Pushable.deliver_now(user, title:, body:, url:)
    end

    private

    def deliver_notification(notification_id)
      return if Rails.application.config.x.vapid.blank?

      # Preloaded with strict loading off: a job has no request, and the
      # belongs_to read would otherwise raise.
      notification = ::Notification.strict_loading(false).includes(:user).find_by(id: notification_id)
      return unless notification&.user

      Shared::Pushable.deliver_now(
        notification.user,
        title: notification.title.presence || "brgen",
        body: notification.body.to_s,
        url: notification.push_path,
        tag: "brgen-#{notification.kind}"
      )
    end
  end
end
