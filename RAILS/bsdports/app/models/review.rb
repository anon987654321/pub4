# frozen_string_literal: true

class Review < ApplicationRecord
  belongs_to :user
  belongs_to :port

  validates :rating, numericality: { only_integer: true, greater_than_or_equal_to: 1, less_than_or_equal_to: 5 }
  validates :content, length: { maximum: 2_000 }, allow_blank: true

  scope :helpful_first, -> { order(helpful_count: :desc, created_at: :desc) }
  scope :recent, -> { order(created_at: :desc) }

  def helpful!
    increment!(:helpful_count)
  end
end
