# frozen_string_literal: true

class Takeaway::MenuItem < ApplicationRecord
  belongs_to :restaurant, class_name: "Takeaway::Restaurant"
  has_one_attached :photo

  validates :name, :price_cents, presence: true
  validates :price_cents, numericality: { greater_than: 0 }

  scope :available, -> { where(available: true) }

  def price_display = "#{price_cents / 100.0} NOK"
end
