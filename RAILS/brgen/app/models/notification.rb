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

  # Live, by refresh rather than by row. The prepend that stood here rendered
  # notifications/_notification on the creating request and published it to a
  # stream nothing subscribed to, and a prepended row would land above the first
  # group header of notifications/_grouped_list. A refresh renders nothing here:
  # it publishes one line to the reader's own stream, and only a notifications
  # page open on their device subscribes and re-fetches itself, groups and count
  # included. NotificationDeliveryJob still carries the old call and is enqueued
  # by nothing.
  after_create_commit do
    if PUSHABLE_KINDS.include?(kind)
      Shared::WebPushJob.perform_later(notification_id: id)
      NativePushJob.perform_later(id) if Apns.configured?
    end
    broadcast_refresh_to(user, :notifications)
  end

  # Where tapping the push lands. Paths are built by hand rather than through
  # url_helpers: a job has no request, so it has no host, and the service worker
  # opens a path anyway. Anything unrecognised falls back to the list rather
  # than guessing.
  def push_path
    return "/notifications" if source_id.blank?

    case source_type
    when "Takeaway::Order", "Marketplace::Order" then "/orders/#{source_id}"
    when "Marketplace::Listing" then "/listings/#{source_id}"
    when "Marketplace::SavedSearch" then "/saved_searches"
    when "Event" then "/events/#{source_id}"
    when "Post" then "/posts/#{source_id}"
    when "Message" then "/conversations"
    when "Community" then "/communities/#{source_id}"
    else "/notifications"
    end
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

    actor_name = strict_safe(:actor)&.display_name || I18n.t("notifications.someone")
    key = "notifications.sentences.#{kind}"
    I18n.t(key, name: actor_name, default: I18n.t("notifications.sentences.generic"))
  end

  def body
    stored = self[:body]
    return stored if stored.present?

    record = association(:notifiable).loaded? ? notifiable : nil
    record.try(:content).presence || record.try(:body).presence || ""
  end
end
