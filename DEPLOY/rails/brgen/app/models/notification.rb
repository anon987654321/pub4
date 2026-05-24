# frozen_string_literal: true

class Notification < ApplicationRecord
  belongs_to :user

  validates :title, presence: true

  scope :unread, -> { where(read_at: nil) }
  scope :recent, -> { order(created_at: :desc) }

  def read?
    read_at.present?
  end
end
