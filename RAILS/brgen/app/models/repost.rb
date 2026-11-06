# frozen_string_literal: true

# A repost is a signal boost, not a copy: it does not create a Post. Post
# includes Shared::Sluggable, whose slug is derived from the title and unique
# per city, so a repost-as-Post would have collided with the thing it was
# reposting. An optional comment is the quote-post variant — still this row,
# still one per user per post. Empty comment is a boost.
class Repost < ApplicationRecord
  include Shared::Notifiable

  COMMENT_MAX = 280

  belongs_to :user
  belongs_to :post, counter_cache: :reposts_count

  validates :user_id, uniqueness: { scope: :post_id }
  validates :comment, length: { maximum: COMMENT_MAX }, allow_blank: true

  scope :by, ->(users) { where(user: users) }
  scope :quoted, -> { where.not(comment: [ nil, "" ]) }

  def quoted? = comment.present?

  # One query per request instead of one per card. Every post on the feed asks
  # whether the viewer reposted it, and 25 exists? calls is the N+1 shape
  # QueryBudgetTest fails on.
  #
  # This plucks the viewer's whole repost set rather than scoping to the posts
  # on screen, which would need every feed controller to pass its page down.
  # The set is per-user and small; if someone ever reposts tens of thousands of
  # things, scope it to the rendered ids instead.
  def self.reposted_post_ids_for(user)
    return Set.new if user.blank?

    load_viewer_memos!(user) if Current.reposted_post_ids.nil?
    Current.reposted_post_ids
  end

  def self.quote_comments_for(user)
    return {} if user.blank?

    load_viewer_memos!(user) if Current.repost_quote_comments.nil?
    Current.repost_quote_comments
  end

  def self.load_viewer_memos!(user)
    rows = where(user_id: user.id).pluck(:post_id, :comment)
    Current.reposted_post_ids = rows.map(&:first).to_set
    Current.repost_quote_comments = rows.each_with_object({}) do |(post_id, comment), memo|
      memo[post_id] = comment if comment.present?
    end
  end
  private_class_method :load_viewer_memos!

  after_create_commit :notify_author
  # Announce is repost. This is the dependency 2.1 had on 1.1.
  after_create_commit :federate

  # Reposting your own post is allowed — it is how you resurface something you
  # wrote, the same as on x.com — but you do not get notified about yourself.
  def federate
    booster = strict_safe(:user)
    return unless booster&.federated?

    Fediverse::DistributeJob.perform_later(
      user_id: booster.id, payload: Fediverse::Serializer.announce(self).to_json
    )
  end

  def notify_author
    author = strict_safe(:post)&.then { |p| User.find_by(id: p.user_id) }
    return if author.nil? || author.id == user_id

    name = strict_safe(:user)&.display_name || "Someone"
    deliver_notification(
      author,
      title: I18n.t(quoted? ? "post.quote_notification" : "post.repost_notification", user: name),
      body: quoted? ? comment : strict_safe(:post)&.title,
      source: self
    )
  end
end
