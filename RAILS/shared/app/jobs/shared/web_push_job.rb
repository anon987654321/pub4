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
  class WebPushJob < ApplicationJob
    queue_as :bulk

    # discard rather than retry: the payload names a message that has already been
    # delivered over Turbo. A retry storm to a dead endpoint helps nobody, and the
    # subscription cleanup below is what actually fixes the cause.
    discard_on ActiveJob::DeserializationError

    def perform(user_id, title:, body:, url:)
      user = User.find_by(id: user_id)
      return unless user

      Shared::Pushable.deliver_now(user, title:, body:, url:)
    end
  end
end
