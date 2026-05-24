# frozen_string_literal: true

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
    return unless idx && idx < STATUSES.length - 1

    update!(status: STATUSES[idx + 1])
    notify_customer!("Order #{status.humanize.downcase}")
  end

  def total_display = "#{total_cents.to_i / 100.0} NOK"

  private

  def notify_customer!(title)
    return unless defined?(Notification)

    user.notifications.create!(
      title: title,
      body: "Your order from #{restaurant.name} is now #{status.humanize.downcase}.",
      source_type: self.class.name,
      source_id: id
    )
  end
end
