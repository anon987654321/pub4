# frozen_string_literal: true

class Comment < ApplicationRecord
  include Shared::Votable
  include Shared::CommentThreading
  tracks_activity created: "CommentCreated", source_vertical: "social", actor: :user

  belongs_to :user
  # counter_cache is opt-in per type on a polymorphic belongs_to: Rails only
  # maintains it where the column exists, and posts is the one that has it.
  belongs_to :commentable, polymorphic: true, touch: true, counter_cache: :comments_count

  include Shared::RichTextLength

  # content holds Tiptap's HTML; the maximum measures the text inside it.
  validates :content, presence: true, length: { minimum: 1 }
  validates_rich_text_length :content, maximum: 10_000

  after_create_commit -> { broadcast_append_to [ commentable, "comments" ], partial: "comments/comment", locals: { comment: self } }

  BEST_SQL = Arel.sql("SUM(COALESCE(votes.value, 0)) DESC")
  CONTROVERSIAL_SQL = Arel.sql("ABS(SUM(votes.value)) ASC")
  HAS_UPVOTE_SQL = Arel.sql("COUNT(CASE WHEN votes.value =  1 THEN 1 END) > 0")
  HAS_DOWNVOTE_SQL = Arel.sql("COUNT(CASE WHEN votes.value = -1 THEN 1 END) > 0")

  scope :kept,          -> { where(removed_at: nil) }
  scope :best,          -> { kept.left_joins(:votes).group(:id).order(BEST_SQL) }
  scope :top,           -> { best }
  scope :new_first,     -> { kept.order(created_at: :desc) }
  scope :controversial, -> {
    left_joins(:votes).group(:id)
      .having(HAS_UPVOTE_SQL)
      .having(HAS_DOWNVOTE_SQL)
      .order(CONTROVERSIAL_SQL)
  }

  def depth
    d = 0
    ancestor_id = parent_id
    while ancestor_id
      d += 1
      ancestor_id = Comment.where(id: ancestor_id).pick(:parent_id)
    end
    d
  end

  LONG_THREAD_THRESHOLD = 20

  def long_thread?
    direct_reply_ids = Comment.where(parent_id: id).pluck(:id)
    total = direct_reply_ids.size + Comment.where(parent_id: direct_reply_ids).count
    total > LONG_THREAD_THRESHOLD
  end

  def has_thread_summary?
    thread_summary.present? && summary_updated_at.present?
  end
end
