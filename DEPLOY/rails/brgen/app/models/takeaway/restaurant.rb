# frozen_string_literal: true

class Takeaway::Restaurant < ApplicationRecord
  belongs_to :user
  has_many :menu_items, class_name: "Takeaway::MenuItem", dependent: :destroy
  has_many :orders, class_name: "Takeaway::Order", dependent: :destroy
  has_many :favorites, class_name: "Takeaway::FavoriteRestaurant", dependent: :destroy
  has_many :reviews, class_name: "Takeaway::Review", dependent: :destroy

  CUISINE_TYPES = %w[Norwegian Italian Chinese Japanese Indian Thai Mexican Pizza Burger Kebab Sushi Vegetarian Vegan].freeze
  CENTS_PER_KRONE = 100.0

  validates :name, :address, :cuisine_type, presence: true
  validates :delivery_fee_cents, :min_order_cents,
            numericality: { greater_than_or_equal_to: 0 }, allow_nil: true

  scope :active, -> { where(active: true) }
  scope :popular, -> { order(rating: :desc) }

  def owner?(account)
    user_id == account&.id
  end

  def delivery_fee_display
    format("%.2f NOK", delivery_fee_cents.to_i / CENTS_PER_KRONE)
  end

  def min_order_display
    format("%.2f NOK", min_order_cents.to_i / CENTS_PER_KRONE)
  end

  def update_rating!
    avg = reviews.average(:rating)
    update_columns(rating: avg&.round(1) || 0)
  end
end
