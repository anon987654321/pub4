# frozen_string_literal: true

class Post < ApplicationRecord
  include ActionText::RichText

  belongs_to :user
  belongs_to :category
  has_rich_text :body
  has_many :comments, dependent: :destroy

  validates :title, presence: true, length: { maximum: 200 }

  scope :pinned,  -> { where(pinned: true) }
  scope :recent,  -> { order(created_at: :desc) }

  def display_author
    anonymous? ? "Anonym" : user.email_address.split("@").first
  end
end
