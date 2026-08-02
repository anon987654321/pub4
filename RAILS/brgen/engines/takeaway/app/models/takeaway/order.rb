# frozen_string_literal: true

class Takeaway::Order < ApplicationRecord
  include Shared::Notifiable
  tracks_activity created: "TakeawayOrderPlaced", source_vertical: "takeaway", actor: :user

  belongs_to :user
  belongs_to :restaurant, class_name: "Takeaway::Restaurant"
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
    "cancelled" => [],
  }.freeze
  CENTS_PER_KRONE = 100.0

  validates :status, inclusion: { in: STATUSES }
  validates :delivery_address, presence: true

  before_validation { self.status ||= "pending" }
  validate :status_transition_allowed, on: :update

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
    update!(subtotal_cents: sub, delivery_fee_cents: fee, total_cents: sub + fee)
  end

  def advance_status!
    transition_to!(next_status)
  end

  def transition_to!(next_status)
    unless may_transition_to?(next_status)
      errors.add(:status, "cannot transition from #{status} to #{next_status}")
      return false
    end

    update!(status: next_status)
    # `user`, `restaurant.name` and `restaurant.user` are all lazy reads, and an
    # order loaded by id (controller, driver request, job) has none of them
    # preloaded. Under strict loading — on in every environment, raising outside
    # development — this raised immediately after update! had committed the new
    # status: the order advanced, the customer was never told, and the caller saw
    # a 500. See Shared::StrictSafeAssociations.
    label = status.humanize.downcase
    restaurant_record = strict_safe(:restaurant)
    deliver_notification(strict_safe(:user),
      title: "Order #{label}",
      body: "Your order from #{restaurant_record&.name} is now #{label}.",
      source: self)
    record_activity!("TakeawayOrderUpdated",
      actor: restaurant_record&.user,
      source_vertical: "takeaway",
      locality: restaurant_record&.[](:city),
      visibility: "private")
    true
  end

  def advanceable?
    next_status.present?
  end

  def may_transition_to?(next_status)
    TRANSITIONS.fetch(status, []).include?(next_status.to_s)
  end

  # Minutes from order placement to the end of each stage. Anchored to
  # created_at (not "now") so the estimate visibly shrinks as the order
  # actually advances, instead of a fixed "25-35 min" string that never
  # reflects what's really happening to this order.
  ETA_MINUTES_BY_STATUS = {
    "pending" => 35,
    "confirmed" => 30,
    "preparing" => 20,
    "out_for_delivery" => 10,
    "delivered" => 0,
  }.freeze

  def estimated_ready_at
    return nil if status == "cancelled"
    created_at + ETA_MINUTES_BY_STATUS.fetch(status, 30).minutes
  end

  # Fraction of the delivery journey complete, for a real (non-decorative)
  # progress fill under the status timeline. nil once terminal — there's
  # nothing left to fill toward.
  def progress_fraction
    return nil if TERMINAL_STATUSES.include?(status)
    stages = STATUSES - TERMINAL_STATUSES
    (stages.index(status).to_i + 1) / stages.size.to_f
  end

  def next_status = TRANSITIONS.fetch(status, []).first
  def cancel! = transition_to!("cancelled")
  def confirm! = transition_to!("confirmed")
  def prepare! = transition_to!("preparing")
  def dispatch! = transition_to!("out_for_delivery")
  def deliver! = transition_to!("delivered")

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

  def status_transition_allowed
    return unless will_save_change_to_status?
    previous_status = status_in_database
    return if previous_status.blank?
    return if TRANSITIONS.fetch(previous_status, []).include?(status)

    errors.add(:status, "cannot transition from #{previous_status} to #{status}")
  end
end
