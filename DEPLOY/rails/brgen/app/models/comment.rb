# frozen_string_literal: true

class Comment < ApplicationRecord
  include Shared::Votable
  include Shared::ActivityTrackable
  tracks_activity created: "CommentCreated", source_vertical: "social", actor: :user

  belongs_to :user
  belongs_to :commentable, polymorphic: true, touch: true
  belongs_to :parent, class_name: "Comment", optional: true

  has_many :replies, class_name: "Comment", foreign_key: :parent_id, dependent: :destroy


  validates :content, presence: true, length: { minimum: 1, maximum: 10000 }

  after_create_commit -> { broadcast_append_to [commentable, "comments"], partial: "comments/comment", locals: { comment: self } }

  scope :best,          -> { left_joins(:votes).group(:id).order("SUM(COALESCE(votes.value, 0)) DESC") }
  scope :top,           -> { best }
  scope :new_first,     -> { order(created_at: :desc) }
  scope :controversial, -> {
    left_joins(:votes).group(:id)
      .having("COUNT(CASE WHEN votes.value =  1 THEN 1 END) > 0")
      .having("COUNT(CASE WHEN votes.value = -1 THEN 1 END) > 0")
      .order("ABS(SUM(votes.value)) ASC")
  }

  def root?  = parent_id.nil?
  def depth  = parent ? parent.depth + 1 : 0

  LONG_THREAD_THRESHOLD = 20

  def long_thread?
    root_replies = replies.count
    total = root_replies + replies.sum { |r| r.replies.count }
    total > LONG_THREAD_THRESHOLD
  end

  def has_thread_summary?
    thread_summary.present? && summary_updated_at.present?
  end
end
