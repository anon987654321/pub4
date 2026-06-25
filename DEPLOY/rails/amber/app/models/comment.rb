# frozen_string_literal: true

class Comment < ApplicationRecord
  belongs_to :user
  belongs_to :commentable, polymorphic: true, touch: true
  belongs_to :parent, class_name: "Comment", optional: true

  has_many :replies, class_name: "Comment", foreign_key: :parent_id, dependent: :destroy

  validates :content, presence: true, length: { maximum: 2000 }

  scope :roots, -> { where(parent_id: nil).order(created_at: :asc) }
end