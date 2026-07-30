# frozen_string_literal: true

# An order that a partner earned on, and what they are owed for it.
#
# The amount is frozen here at attribution time rather than recomputed from the
# programme on read. A merchant is free to change their rate tomorrow; what a
# partner earned yesterday is settled.
class Partner::Conversion < ApplicationRecord
  self.table_name = "partner_conversions"

  belongs_to :membership, class_name: "Partner::Membership"
  belongs_to :click, class_name: "Partner::Click", optional: true
  belongs_to :order, class_name: "Marketplace::Order"

  has_one :program, through: :membership
  has_one :partner, through: :membership, source: :user

  STATUSES = %w[pending approved rejected paid].freeze

  validates :status, inclusion: { in: STATUSES }
  validates :order_id, uniqueness: true
  validates :order_value_cents, :commission_cents,
            numericality: { greater_than_or_equal_to: 0, only_integer: true }
  validate :commission_within_order_value

  scope :payable, -> { where(status: "approved") }
  scope :ripe, ->(now = Time.current) { where(status: "pending", payable_after: ..now) }

  def approve!
    update!(status: "approved", approved_at: Time.current)
  end

  def reject!(reason)
    update!(status: "rejected", rejected_reason: reason.to_s.first(200))
  end

  def mark_paid!
    raise ArgumentError, "only an approved conversion can be paid" unless status == "approved"

    update!(status: "paid", paid_at: Time.current)
  end

  # The merchant's return window has closed and nobody rejected it.
  #
  # Deliberately not a background job that pays automatically: approving means
  # money leaves, and it should be something a person or an explicit task does,
  # not something that happens because a timestamp passed.
  def self.approve_ripe!(now: Time.current)
    ripe(now).find_each(&:approve!).then { ripe(now).count }
  end

  private

  def commission_within_order_value
    return if commission_cents.to_i <= order_value_cents.to_i

    errors.add(:commission_cents, "cannot exceed the order value")
  end
end
