# frozen_string_literal: true

class Notification < ApplicationRecord
  # order — something the user is waiting on moved: an order confirmed,
  #         dispatched, shipped, delivered, paid.
  # alert — something they asked to be told about happened: a saved search
  #         matched, a listing is about to lapse, an event they said they were
  #         coming to was cancelled.
  #
  # Both are new, and both are pushable. Everything on those paths was written
  # as "custom" — the column default, because Shared::Notifiable dropped the
  # kind on the title/body branch — so none of it could ever reach a lock
  # screen no matter how time-critical it was.
  KINDS = %w[like reaction follow mention reply message match order alert custom].freeze

  belongs_to :user
  belongs_to :actor, class_name: "User", optional: true
  belongs_to :notifiable, polymorphic: true, optional: true

  validates :kind, inclusion: { in: KINDS }

  scope :unread, -> { where(read_at: nil) }
  scope :recent, -> { order(created_at: :desc) }

  # High-signal kinds also fire a browser push; likes/reactions stay in-app only
  # so the lock screen doesn't become noise. `order` and `alert` are here
  # because both are things the reader is actively waiting on — a parcel moving,
  # a saved search finally matching — which is the case a push is for.
  PUSHABLE_KINDS = %w[message match reply mention follow order alert].freeze

  after_create_commit do
    broadcast_prepend_to "brgen:notifications:#{user_id}"
    WebPushJob.perform_later(id) if PUSHABLE_KINDS.include?(kind)
  end

  def read?
    read_at.present?
  end

  def mark_as_read!
    update!(read_at: Time.current)
  end

  # These two shadow real columns. notifications.title and notifications.body
  # are written by every title/body caller — Shared::Notifiable's custom branch,
  # which is how an order update, a saved-search match and a listing expiry all
  # arrive — and the methods below ignored them completely: the case fell to
  # "New notification" with an empty body, in the list, in the row partial, and
  # in the web-push payload.
  #
  # The stored value wins where there is one; the derived sentence stays for the
  # structured social kinds, which store neither.
  def title
    stored = self[:title]
    return stored if stored.present?

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
    stored = self[:body]
    return stored if stored.present?

    notifiable.try(:content).presence || notifiable.try(:body).presence || ""
  end
end
