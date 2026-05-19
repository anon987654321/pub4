# frozen_string_literal: true

class Comment < ApplicationRecord
  belongs_to :user
  belongs_to :post
  belongs_to :parent, class_name: "Comment", optional: true
  has_many :replies, class_name: "Comment", foreign_key: :parent_id, dependent: :destroy

  validates :content, presence: true, length: { maximum: 3000 }

  scope :roots, -> { where(parent_id: nil).order(created_at: :asc) }

  after_create_commit -> { broadcast_append_to [post, "comments"] }

  def display_author
    anonymous? ? "Anonym" : user.email_address.split("@").first
  end
end
