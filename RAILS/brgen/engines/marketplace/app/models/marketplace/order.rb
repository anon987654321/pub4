# frozen_string_literal: true

class Marketplace::Order < ApplicationRecord
  include Shared::Notifiable
  tracks_activity created: "MarketplaceOrder", source_vertical: "marketplace", actor: :buyer

  belongs_to :buyer,   class_name: "User"
  belongs_to :listing, class_name: "Marketplace::Listing"
  # Optional, because a per-listing offer to a stranger has no basket above it —
  # that shape is still how classifieds work here. See Marketplace::Checkout.
  belongs_to :checkout, class_name: "Marketplace::Checkout",
             foreign_key: :marketplace_checkout_id, optional: true, inverse_of: :orders

  STATUSES = %w[pending pending_payment paid accepted declined completed].freeze
  # Fulfilment is a separate axis from payment. A paid order that has not
  # shipped and a shipped order awaiting payment are both real, and collapsing
  # them into one column is why "where is my parcel" goes unanswered.
  FULFILMENT_STATUSES = %w[unfulfilled shipped delivered cancelled].freeze
  PAYMENT_STATUSES = %w[unpaid pending paid failed refunded].freeze
  PAYMENT_PROVIDERS = %w[stripe vipps].freeze

  validates :status, inclusion: { in: STATUSES }
  validates :fulfilment_status, inclusion: { in: FULFILMENT_STATUSES }
  validates :payment_status, inclusion: { in: PAYMENT_STATUSES }
  validates :payment_provider, inclusion: { in: PAYMENT_PROVIDERS }, allow_nil: true
  before_validation { self.status ||= "pending" }
  before_validation { self.payment_status ||= "unpaid" }
  before_validation { self.fulfilment_status ||= "unfulfilled" }

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
  def total_display = Shared::MoneyDisplay.format(total_cents, listing.currency || "NOK")

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

  # The payment services used to read order.listing.currency and .title
  # directly, which meant only a single-listing order could ever be paid. They
  # now ask the payable, so a Checkout — which has no single listing — goes
  # through the same guarded path rather than a second one beside it.
  def payment_currency = strict_safe_attribute(:listing, :currency).presence || "NOK"
  def payment_description = listing_title

  def payable?
    payment_status.in?(%w[unpaid pending failed]) && status.in?(%w[pending pending_payment])
  end

  # Shipping is the seller telling the buyer where the parcel is. Notified on
  # the transition rather than left as a status for the buyer to poll, because
  # nobody polls an order page.
  def ship!(tracking_code: nil, carrier: nil)
    update!(
      fulfilment_status: "shipped",
      tracking_code: tracking_code,
      carrier: carrier,
      shipped_at: Time.current
    )
    detail = tracking_code.presence ? "#{listing_title} — #{carrier.presence || 'Tracking'}: #{tracking_code}" : listing_title
    deliver_notification(buyer_record, title: "On its way", body: detail, source: self)
  end

  def mark_delivered!
    update!(fulfilment_status: "delivered", delivered_at: Time.current)
    deliver_notification(buyer_record, title: "Delivered", body: listing_title, source: self)
  end
end
