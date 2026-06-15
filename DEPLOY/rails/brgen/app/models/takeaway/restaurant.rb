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
  scope :search, ->(q) {
    term = q.to_s.strip
    return none if term.empty?

    ids = connection.select_values(
      sanitize_sql_array(["SELECT rowid FROM takeaway_restaurants_fts WHERE takeaway_restaurants_fts MATCH ?", term])
    )
    ids.any? ? where(id: ids) : none
  }
  scope :ranked_by_distance, ->(lat, lng) {
    return popular if lat.blank? || lng.blank?

    lat = lat.to_f
    lng = lng.to_f
    order(
      Arel.sql(sanitize_sql_array([
        "CASE WHEN latitude IS NOT NULL AND longitude IS NOT NULL THEN " \
        "((latitude - ?) * (latitude - ?) + (longitude - ?) * (longitude - ?)) " \
        "ELSE 999 END ASC, rating DESC",
        lat, lat, lng, lng
      ]))
    )
  }

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
