# frozen_string_literal: true

class Marketplace::Payout < ApplicationRecord
  include Shared::StrictSafeAssociations

  self.table_name = "marketplace_payouts"

  STATUSES = %w[pending sent blocked].freeze

  belongs_to :store, class_name: "Marketplace::Store"
  belongs_to :order, class_name: "Marketplace::Order", optional: true

  validates :status, inclusion: { in: STATUSES }
  validates :amount_cents, numericality: { greater_than: 0 }
  validates :currency, presence: true, length: { maximum: 8 }

  scope :pending, -> { where(status: "pending") }

  def pending? = status == "pending"
  def sent? = status == "sent"

  # Held until the Norwegian return window (14 days from delivery) has closed
  # with the order still paid. Paying out on `mark_paid!` then refunding is how
  # the platform goes negative: Checkout lands on the platform, the transfer
  # pushes to Connect, and a later refund has nothing left to debit.
  def releasable?
    return false unless pending?
    return false unless connect_ready?

    payment_status, fulfilment_status, delivered_at = Marketplace::Order.where(id: order_id)
      .pick(:payment_status, :fulfilment_status, :delivered_at)
    return false unless payment_status == "paid" && fulfilment_status == "delivered"
    return false if delivered_at.blank? || delivered_at > Marketplace::Return::WINDOW.ago
    return false if Marketplace::Return.open_returns.where(order_id: order_id).exists?

    true
  end

  # Fail-closed. A missing Connect account or Stripe key leaves the row pending;
  # it is never marked sent on a local write alone.
  def release!
    raise ArgumentError, "payout is not pending" unless pending?
    raise ArgumentError, "payout is held until the return window closes" unless releasable?

    transfer_id = Marketplace::Payments::StripeTransfer.submit!(payout: self)
    update!(status: "sent", stripe_transfer_id: transfer_id, sent_at: Time.current, blocked_reason: nil)
  end

  # A received return must not leave this row sendable. Reverse first if Stripe
  # already moved the money; void a pending row locally.
  def clawback_or_void!
    if sent? && stripe_transfer_id.present?
      Marketplace::Payments::StripeTransfer.reverse!(payout: self)
    end
    update!(status: "blocked", blocked_reason: "returned") unless status == "blocked"
  end

  private

  def connect_ready?
    destination = Marketplace::Store.where(id: store_id).pick(:stripe_connect_id).to_s
    destination.match?(Marketplace::Payments::StripeTransfer::ACCOUNT)
  end
end
