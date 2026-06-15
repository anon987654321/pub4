# frozen_string_literal: true

class Post < ApplicationRecord
  # Engine-ize: use Shared.concern for consistency
  include Shared.concern(:Votable) rescue include Shared::Votable
  include Shared.concern(:Commentable) rescue include Shared::Commentable
  include Shared.concern(:Taggable) rescue include Shared::Taggable
  include Shared.concern(:ActivityTrackable) rescue include Shared::ActivityTrackable  # Wave 1: mandatory spine

  has_one_attached :image

  belongs_to :user
  belongs_to :community, optional: true


  has_many :taggings, dependent: :destroy
  has_many :hashtags, through: :taggings
  has_many :mentions, dependent: :destroy

  validates :title,   presence: true, length: { maximum: 300 }
  validates :content, length: { maximum: 40_000 }

  broadcasts_refreshes

  VOTE_SQL = Arel.sql("SUM(COALESCE(votes.value,0)) DESC, posts.created_at DESC")
  TOP_SQL  = Arel.sql("SUM(COALESCE(votes.value,0)) DESC")

  scope :hot,    -> { left_joins(:votes).group(:id).order(VOTE_SQL) }
  scope :fresh,  -> { order(created_at: :desc) }
  scope :top,    -> { left_joins(:votes).group(:id).order(TOP_SQL) }
  scope :search, ->(q) {
    ids = connection.select_values(sanitize_sql_array(["SELECT rowid FROM posts_fts WHERE posts_fts MATCH ?", q]))
    ids.any? ? where(id: ids) : none
  }

  def comment_count = comments.count
  def author_name   = (anonymous? || user&.guest?) ? "anon" : (user&.username.presence || "anon")
end
