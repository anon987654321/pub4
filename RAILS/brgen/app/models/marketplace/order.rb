# frozen_string_literal: true

class Marketplace::Order < ApplicationRecord
  include Shared::Notifiable
  tracks_activity created: "MarketplaceOrder", source_vertical: "marketplace", actor: :buyer

  belongs_to :buyer,   class_name: "User"
  belongs_to :listing, class_name: "Marketplace::Listing"

  STATUSES = %w[pending pending_payment paid accepted declined completed].freeze
  PAYMENT_STATUSES = %w[unpaid pending paid failed refunded].freeze
  PAYMENT_PROVIDERS = %w[stripe vipps].freeze

  validates :status, inclusion: { in: STATUSES }
  validates :payment_status, inclusion: { in: PAYMENT_STATUSES }
  validates :payment_provider, inclusion: { in: PAYMENT_PROVIDERS }, allow_nil: true
  before_validation { self.status ||= "pending" }
  before_validation { self.payment_status ||= "unpaid" }

  # mark_paid! notifies the seller, and a PSP webhook finds the order by id with
  # nothing preloaded. Walking listing.user there raised StrictLoadingViolation
  # *after* update! had committed payment_status=paid: the money was recorded,
  # neither party was notified, and Stripe got a 500 for a payment that had
  # actually succeeded — then the retry skipped the work because the order was
  # no longer payable?. See Shared::StrictSafeAssociations.
  def seller
    return listing.user if association(:listing).loaded? && listing.association(:user).loaded?

    seller_id = association(:listing).loaded? ? listing.user_id : Marketplace::Listing.where(id: listing_id).pick(:user_id)
    User.strict_loading(false).find_by(id: seller_id)
  end

  # Read by the notification bodies below; a lazy association read on any order
  # that was found by id.
  def listing_title = strict_safe_attribute(:listing, :title)

  # Notification recipient. belongs_to :buyer is lazily loaded too.
  def buyer_record = strict_safe(:buyer)

  # Cart-like helpers (pending orders act as the buyer's cart)
  def total_cents = (price_cents.presence || listing.price_cents || 0) * (quantity.presence || 1).to_i
  def total_display = "#{total_cents / 100.0} #{listing.currency || 'NOK'}"

  def accept!
    update!(status: "accepted")
    deliver_notification(buyer_record, title: "Offer accepted", body: "Your offer for #{listing_title} was accepted.", source: self)
  end

  def decline!
    update!(status: "declined")
    deliver_notification(buyer_record, title: "Offer declined", body: "Your offer for #{listing_title} was declined.", source: self)
  end

  def mark_payment_pending!(provider:, reference:)
    update!(
      payment_provider: provider,
      payment_status: "pending",
      payment_reference: reference,
      status: "pending_payment"
    )
  end

  def mark_paid!(reference: payment_reference)
    update!(
      payment_status: "paid",
      payment_reference: reference.presence || payment_reference,
      paid_at: Time.current,
      status: "paid"
    )
    title = listing_title
    deliver_notification(seller, title: "Payment received", body: "Payment for #{title} cleared.", source: self)
    deliver_notification(buyer_record, title: "Payment confirmed", body: "Your payment for #{title} is confirmed.", source: self)
  end

  def payable?
    payment_status.in?(%w[unpaid pending failed]) && status.in?(%w[pending pending_payment])
  end
end
