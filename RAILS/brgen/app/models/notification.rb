# frozen_string_literal: true

class Notification < ApplicationRecord
  KINDS = %w[like reaction follow mention reply message match custom].freeze

  belongs_to :user
  belongs_to :actor, class_name: "User", optional: true
  belongs_to :notifiable, polymorphic: true, optional: true

  validates :kind, inclusion: { in: KINDS }

  scope :unread, -> { where(read_at: nil) }
  scope :recent, -> { order(created_at: :desc) }

  # High-signal kinds also fire a browser push; likes/reactions stay in-app only
  # so the lock screen doesn't become noise.
  PUSHABLE_KINDS = %w[message match reply mention follow].freeze

  after_create_commit do
    broadcast_prepend_later_to "brgen:notifications:#{user_id}"
    WebPushJob.perform_later(id) if PUSHABLE_KINDS.include?(kind)
  end

  def read?
    read_at.present?
  end

  def mark_as_read!
    update!(read_at: Time.current)
  end

  def title
    actor_name = actor&.display_name || "Someone"
    case kind
    when "follow" then "#{actor_name} followed you"
    when "like", "reaction" then "#{actor_name} reacted to your post"
    when "mention" then "#{actor_name} mentioned you"
    when "reply" then "#{actor_name} replied to your comment"
    when "message" then "New message from #{actor_name}"
    when "match" then "It's a match with #{actor_name}"
    else "New notification"
    end
  end

  def body
    notifiable.try(:content).presence || notifiable.try(:body).presence || ""
  end
end
