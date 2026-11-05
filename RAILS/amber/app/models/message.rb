# frozen_string_literal: true

class Message < ApplicationRecord
  belongs_to :sender, class_name: "User"
  belongs_to :recipient, class_name: "User"

  validates :body, presence: true, length: { maximum: 2_000 }

  scope :recent, -> { order(created_at: :desc) }
  scope :unread, -> { where(read_at: nil) }
  scope :involving, ->(user) { where(sender: user).or(where(recipient: user)) }
  scope :between, ->(user, other) { where(sender: user, recipient: other).or(where(sender: other, recipient: user)) }
  # The newest message with each person `user` has written to or heard from:
  # the inbox is one row per person.
  scope :latest_per_partner, ->(user) { where(id: involving(user).group(partner_of(user)).select("MAX(messages.id)")) }

  # The person on the other side of each of `user`'s messages, as SQL.
  def self.partner_of(user)
    Arel.sql(sanitize_sql_array([ "CASE WHEN sender_id = ? THEN recipient_id ELSE sender_id END", user.id ]))
  end

  def self.partner_ids(user) = involving(user).select(partner_of(user))

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
