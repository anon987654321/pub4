# frozen_string_literal: true

class Comment < ApplicationRecord
  belongs_to :post, counter_cache: :comments_count
  belongs_to :user
  belongs_to :parent, class_name: "Comment", optional: true
  has_many :replies, class_name: "Comment", foreign_key: :parent_id, dependent: :destroy

  validates :content, presence: true, length: { maximum: 5000 }

  scope :roots,    -> { where(parent_id: nil).order(created_at: :asc) }
  scope :approved, -> { where(approved: true) }

  after_create_commit :broadcast_comment

  private

  def broadcast_comment
    broadcast_append_to [post, "comments"], partial: "comments/comment", locals: { comment: self }

  end
end
