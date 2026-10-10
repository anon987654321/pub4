# frozen_string_literal: true

class MasterMessageReplyJob < ApplicationJob
  queue_as :default

  def perform(message_id)
    message = Message.includes(:sender, :recipient).find_by(id: message_id)
    return unless message&.master_message?

    sender_id = message.sender_id
    master_id = message.recipient_id
    messages = Message.where(sender_id: [ sender_id, master_id ], recipient_id: [ sender_id, master_id ])
                      .includes(:sender).order(:created_at).last(24)
    reply = Shared::MasterMessenger.new.reply(
      messages:, sender: message.sender, message:,
      session_key: "amber:#{[ sender_id, master_id ].sort.join("-")}", channel: "amber-messenger"
    )
    return if reply.blank?

    master = message.recipient
    master.sent_messages.create!(recipient: message.sender, body: reply.first(2_000))
  end
end
