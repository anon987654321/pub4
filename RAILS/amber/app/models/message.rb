# frozen_string_literal: true

class Message < ApplicationRecord
  belongs_to :sender, class_name: "User"
  belongs_to :recipient, class_name: "User"

  validates :body, presence: true, length: { maximum: 2_000 }

  scope :recent, -> { order(created_at: :desc) }
  scope :unread, -> { where(read_at: nil) }

  after_create_commit :enqueue_master_reply, if: :master_message?
  after_create_commit :broadcast_live

  def master_message?
    !sender.bot? && recipient&.master_bot?
  end

  def read! = update!(read_at: Time.current)

  private

  def enqueue_master_reply
    MasterMessageReplyJob.perform_later(id)
  end

  def broadcast_live
    fresh = Message.includes(:sender, :recipient).find(id)
    [ sender_id, recipient_id ].uniq.each do |viewer_id|
      fresh.broadcast_append_to(
        "amber:messages:#{viewer_id}",
        target: "amber-message-log",
        partial: "messages/message",
        locals: { message: fresh, viewer_id: viewer_id }
      )
    end
  end
end
