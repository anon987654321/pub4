# frozen_string_literal: true

class Post < ApplicationRecord
  include CityTenantable

  include Shared::Votable
  include Shared::Commentable
  include Shared::Taggable
  include Shared::Reactable
  include Shared::MediaProcessable
  tracks_activity created: "PostCreated", source_vertical: "social", actor: :user

  has_one_attached :image
  has_one_attached :video
  has_one_attached :audio
  process_media_variants :image, variants: {
    card: { resize_to_limit: [ 800, 800 ], format: :webp },
    hero: { resize_to_limit: [ 1_200, 1_200 ], format: :webp }
  }

  belongs_to :user
  belongs_to :community, optional: true

  has_many :mentions, dependent: :destroy

  validates :title,   presence: true, length: { maximum: 300 }
  validates :content, length: { maximum: 40_000 }

  broadcasts_refreshes

  VOTE_SQL = Arel.sql("SUM(COALESCE(votes.value,0)) DESC, posts.created_at DESC")
  TOP_SQL  = Arel.sql("SUM(COALESCE(votes.value,0)) DESC")
  READING_WORDS_PER_MINUTE = 200

  scope :hot,    -> { left_joins(:votes).group(:id).order(VOTE_SQL) }
  scope :fresh,  -> { order(created_at: :desc) }
  scope :top,    -> { left_joins(:votes).group(:id).order(TOP_SQL) }
  scope :search, ->(q) {
    ids = connection.select_values(sanitize_sql_array([ "SELECT rowid FROM posts_fts WHERE posts_fts MATCH ?", q ]))
    ids.any? ? where(id: ids) : none
  }

  def comment_count = comments.count
  def author_name   = (anonymous? || user&.guest?) ? "anon" : (user&.username.presence || "anon")

  # Same anon check as author_name -- an identicon is only safe to show
  # alongside a real name. Showing it under "anon" too would give every
  # anonymous post from the same user a matching visual signature, letting
  # readers correlate "anon" posts by eye even though the name can't.
  def author_avatar_url
    return nil if anonymous? || user&.guest?
    user&.avatar_url
  end

  def reading_time_minutes
    text = ActionView::Base.full_sanitizer.sanitize(content.to_s)
    words = text.scan(/[[:alnum:]]+(?:['-][[:alnum:]]+)*/).size
    return 0 if words.zero?

    (words / READING_WORDS_PER_MINUTE.to_f).ceil
  end
end
