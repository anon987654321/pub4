# frozen_string_literal: true

class Message < ApplicationRecord
  belongs_to :sender, class_name: "User"
  belongs_to :recipient, class_name: "User"

  validates :body, presence: true, length: { maximum: 2_000 }

  scope :recent, -> { order(created_at: :desc) }
  scope :unread, -> { where(read_at: nil) }

  def read! = update!(read_at: Time.current)
end
