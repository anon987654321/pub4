# frozen_string_literal: true

# Runs off the request cycle so an LLM round-trip never blocks a human's send.
# Jobs run tenant-less, which is exactly what city-less bot accounts need.
class ChannelBotReplyJob < ApplicationJob
  queue_as :default

  def perform(message_id)
    message = Message.find_by(id: message_id) or return
    ChannelBot.reply_to(message)
  end
end
