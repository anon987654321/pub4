class Takeaway::Restaurant < ApplicationRecord
  belongs_to :user
  has_many :menu_items, class_name: "Takeaway::MenuItem", dependent: :destroy
  has_many :orders,     class_name: "Takeaway::Order",    dependent: :destroy

  CUISINE_TYPES = %w[Norwegian Italian Chinese Japanese Indian Thai Mexican Pizza Burger Kebab Sushi Vegetarian Vegan].freeze

  validates :name, :address, :cuisine_type, presence: true
  validates :delivery_fee_cents, :min_order_cents,
            numericality: { greater_than_or_equal_to: 0 }, allow_nil: true

  scope :active,  -> { where(active: true) }
  scope :popular, -> { order(rating: :desc) }

  def update_rating!
    avg = orders.joins(:reviews).average("takeaway_reviews.rating") rescue nil
    update_columns(rating: avg&.round(1) || 0)
  end
end
