# frozen_string_literal: true

# A repost is a signal boost, not a copy: it carries no content of its own and
# does not create a Post. Post includes Shared::Sluggable, whose slug is derived
# from the title and unique per city, so a repost-as-Post would have collided
# with the thing it was reposting.
#
# The quote-post variant — a repost that does carry a comment — is not built.
# See RAILS/TODO.md 1.1.
class Repost < ApplicationRecord
  include Shared::Notifiable

  belongs_to :user
  belongs_to :post, counter_cache: :reposts_count

  validates :user_id, uniqueness: { scope: :post_id }

  scope :by, ->(users) { where(user: users) }

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

    Current.reposted_post_ids ||= where(user_id: user.id).pluck(:post_id).to_set
  end

  after_create_commit :notify_author

  # Reposting your own post is allowed — it is how you resurface something you
  # wrote, the same as on x.com — but you do not get notified about yourself.
  def notify_author
    author = strict_safe(:post)&.then { |p| User.find_by(id: p.user_id) }
    return if author.nil? || author.id == user_id

    deliver_notification(
      author,
      title: I18n.t("post.repost_notification", user: strict_safe(:user)&.display_name || "Someone"),
      body: strict_safe(:post)&.title,
      source: self
    )
  end
end
