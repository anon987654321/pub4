# frozen_string_literal: true

class Takeaway::Order < ApplicationRecord
  belongs_to :user
  belongs_to :restaurant, class_name: "Takeaway::Restaurant"
  has_many :order_items, class_name: "Takeaway::OrderItem", dependent: :destroy

  STATUSES = %w[pending confirmed preparing out_for_delivery delivered cancelled].freeze
  CENTS_PER_KRONE = 100.0

  validates :status, inclusion: { in: STATUSES }
  validates :delivery_address, presence: true

  before_validation { self.status ||= "pending" }

  scope :active, -> { where.not(status: %w[delivered cancelled]) }
  scope :recent, -> { order(created_at: :desc) }

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
    record_status_activity!
  end

  def subtotal_display
    amount_display(subtotal_cents)
  end

  def delivery_fee_display
    amount_display(delivery_fee_cents)
  end

  def total_display
    amount_display(total_cents)
  end

  private

  def amount_display(cents)
    format("%.2f NOK", cents.to_i / CENTS_PER_KRONE)
  end

  def notify_customer!(title)
    return unless defined?(Notification)

    user.notifications.create!(
      title: title,
      body: "Your order from #{restaurant.name} is now #{status.humanize.downcase}.",
      source_type: self.class.name,
      source_id: id
    )
  end

  def record_status_activity!
    return unless defined?(ActivityEventRecorder)

    ActivityEventRecorder.call(
      actor: restaurant.user,
      event_name: "TakeawayOrderUpdated",
      object: self,
      source_vertical: "takeaway",
      locality: restaurant.city,
      visibility: "private"
    )
  end
end
