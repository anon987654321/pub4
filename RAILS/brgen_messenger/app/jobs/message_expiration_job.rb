# frozen_string_literal: true

class MessageExpirationJob < ApplicationJob
  queue_as :default

  def perform(message_id)
    message = Message.find_by(id: message_id)
    return unless message&.expired?

    message.expire!
  end
end
