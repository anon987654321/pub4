# frozen_string_literal: true

class Takeaway::Order < ApplicationRecord
  include Shared::Notifiable
  include Lifecycle
  include Delivery
  include GroupTicket

  tracks_activity created: "TakeawayOrderPlaced", source_vertical: "takeaway", actor: :user

  belongs_to :user
  belongs_to :restaurant, class_name: "Takeaway::Restaurant"
  # delivery_driver_id and its composite [delivery_driver_id, status] index have
  # been on this table since it was created, and Takeaway::DeliveryDriver has
  # had the matching has_many :orders — but there was no belongs_to here and
  # nothing ever wrote the column, so every order went out for delivery with no
  # courier attached. See Delivery#dispatch_driver_id.
  belongs_to :delivery_driver, class_name: "Takeaway::DeliveryDriver", optional: true
  has_many :order_items, class_name: "Takeaway::OrderItem", dependent: :destroy
  has_many :reviews, class_name: "Takeaway::Review", dependent: :destroy

  STATUSES = %w[pending confirmed preparing out_for_delivery delivered cancelled].freeze
  TERMINAL_STATUSES = %w[delivered cancelled].freeze
  TRANSITIONS = {
    "pending" => %w[confirmed cancelled],
    "confirmed" => %w[preparing cancelled],
    "preparing" => %w[out_for_delivery cancelled],
    "out_for_delivery" => %w[delivered],
    "delivered" => [],
    "cancelled" => []
  }.freeze
  CENTS_PER_KRONE = 100.0

  validates :status, inclusion: { in: STATUSES }
  validates :delivery_address, presence: true

  before_validation { self.status ||= "pending" }
  validate :status_transition_allowed, on: :update
  validate :meets_minimum_order, on: :create
  validate :has_line_items, on: :create

  scope :active, -> { where.not(status: TERMINAL_STATUSES) }
  scope :recent, -> { order(created_at: :desc) }

  def calculate_totals!
    # Use in-memory association target so create-with-build works under strict_loading.
    items = order_items.target
    sub = items.sum { |oi| oi.unit_price_cents.to_i * oi.quantity.to_i }
    # The comment above covers order_items, but the delivery fee was still a lazy
    # belongs_to read — so this raised on any order loaded from the database
    # rather than built in memory.
    fee = strict_safe_attribute(:restaurant, :delivery_fee_cents).to_i
    # The tip is part of what is charged, so it belongs in the total rather than
    # being added at some later point nobody can find.
    update!(subtotal_cents: sub, delivery_fee_cents: fee, total_cents: sub + fee + tip_cents.to_i)
  end

  # A new pending order with the same address and whatever is still on the
  # menu. Tip and scheduled_for stay off — those are per-ticket decisions.
  def build_reorder
    kitchen = strict_safe(:restaurant)
    copy = kitchen.orders.build(
      user: strict_safe(:user),
      delivery_address: delivery_address,
      special_instructions: special_instructions
    )
    order_items.each do |oi|
      item = oi.association(:menu_item).loaded? ? oi.menu_item : oi.strict_safe(:menu_item)
      # available_for_order? reads item.restaurant. Point the inverse at the
      # kitchen we already have so the create validation does not lazy-load.
      next unless item&.available? && kitchen.active?

      item.association(:restaurant).target = kitchen unless item.association(:restaurant).loaded?
      copy.order_items.build(
        menu_item: item,
        quantity: oi.quantity,
        unit_price_cents: item.price_cents
      )
    end
    copy
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

  def tip_display
    amount_display(tip_cents)
  end

  private

  def amount_display(cents)
    Shared::MoneyDisplay.format(cents)
  end

  # The restaurant advertises a minimum-order threshold (shown as a chip on its
  # page); before this, checkout ignored it and let a 30-kr order through against
  # a 150-kr minimum. Read items in memory (like calculate_totals!) so this holds
  # during create-with-build under strict loading; `restaurant` is the in-memory
  # object the controller assigned, not a lazy DB read.
  def has_line_items
    return if order_items.target.any?

    errors.add(:base, :empty_order)
  end

  def meets_minimum_order
    min = restaurant&.min_order_cents.to_i
    return if min <= 0

    sub = order_items.target.sum { |oi| oi.unit_price_cents.to_i * oi.quantity.to_i }
    return if sub >= min

    errors.add(:base, :below_minimum, restaurant: restaurant.name, minimum: restaurant.min_order_display, subtotal: amount_display(sub))
  end
end
