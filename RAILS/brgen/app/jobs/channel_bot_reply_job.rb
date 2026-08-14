# frozen_string_literal: true

# Runs off the request cycle so an LLM round-trip never blocks a human's send.
# Jobs run tenant-less, which is exactly what city-less bot accounts need.
class ChannelBotReplyJob < ApplicationJob
  queue_as :default

  # Loaded the way Message#broadcast_to_logs loads it, and for the same reason.
  # ApplicationRecord sets strict_loading_by_default = true in every
  # environment, ChannelBot.reply_to reads message.conversation, and a plain
  # `Message.find_by` raises:
  #
  #   ActiveRecord::StrictLoadingViolationError: `Message` is marked for
  #   strict_loading. The Conversation association named `:conversation` cannot
  #   be lazily loaded.
  #
  # Seen in production on 2026-08-14, three attempts then "Stopped retrying".
  # It had been invisible because no Solid Queue worker runs on this box, so the
  # job had never executed at all — the first time anything ran the queue, this
  # was waiting in it. Two faults stacked: the bots did not reply because nothing
  # ran the job, and would not have replied if it had.
  def perform(message_id)
    message = Message.strict_loading(false).includes(:sender, :conversation).find_by(id: message_id) or return
    ChannelBot.reply_to(message)
  end
end
