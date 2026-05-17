class Takeaway::Order < ApplicationRecord
  belongs_to :user
  belongs_to :restaurant, class_name: "Takeaway::Restaurant"
  has_many :order_items, class_name: "Takeaway::OrderItem", dependent: :destroy

  STATUSES = %w[pending confirmed preparing out_for_delivery delivered cancelled].freeze

  validates :status, inclusion: { in: STATUSES }
  validates :delivery_address, presence: true

  before_validation { self.status ||= "pending" }

  scope :active,  -> { where.not(status: %w[delivered cancelled]) }
  scope :recent,  -> { order(created_at: :desc) }

  def calculate_totals!
    sub = order_items.sum { |oi| oi.unit_price_cents * oi.quantity }
    fee = restaurant.delivery_fee_cents.to_i
    update!(subtotal_cents: sub, delivery_fee_cents: fee, total_cents: sub + fee)
  end

  def advance_status!
    idx = STATUSES.index(status)
    update!(status: STATUSES[idx + 1]) if idx && idx < STATUSES.length - 1
  end

  def total_display   = "#{total_cents.to_i / 100.0} NOK"
end
