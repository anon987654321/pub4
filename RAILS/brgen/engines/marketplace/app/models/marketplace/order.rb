# frozen_string_literal: true

class Marketplace::Order < ApplicationRecord
  include Shared::Notifiable
  tracks_activity created: "MarketplaceOrder", source_vertical: "marketplace", actor: :buyer

  belongs_to :buyer,   class_name: "User"
  belongs_to :listing, class_name: "Marketplace::Listing"
  # Which version of the listing this is for. Optional, because a classifieds
  # listing has no variants and that is most of them; required by validation
  # when the listing does have them, or the order is for "a shirt" and the
  # seller cannot pack it.
  belongs_to :variant, class_name: "Marketplace::Variant", optional: true
  # Optional, because a per-listing offer to a stranger has no basket above it —
  # that shape is still how classifieds work here. See Marketplace::Checkout.
  has_many :returns, class_name: "Marketplace::Return", dependent: :destroy
  belongs_to :checkout, class_name: "Marketplace::Checkout",
             foreign_key: :marketplace_checkout_id, optional: true, inverse_of: :orders

  STATUSES = %w[pending pending_payment paid accepted declined completed].freeze
  # Fulfilment is a separate axis from payment. A paid order that has not
  # shipped and a shipped order awaiting payment are both real, and collapsing
  # them into one column is why "where is my parcel" goes unanswered.
  FULFILMENT_STATUSES = %w[unfulfilled shipped delivered cancelled returned].freeze
  PAYMENT_STATUSES = %w[unpaid pending paid failed refunded].freeze
  PAYMENT_PROVIDERS = %w[stripe vipps].freeze

  validates :status, inclusion: { in: STATUSES }
  validates :fulfilment_status, inclusion: { in: FULFILMENT_STATUSES }
  validates :payment_status, inclusion: { in: PAYMENT_STATUSES }
  validates :payment_provider, inclusion: { in: PAYMENT_PROVIDERS }, allow_nil: true
  validate :listing_must_be_live, on: :create
  validate :variant_belongs_to_listing
  validate :variant_chosen_when_the_listing_has_them, on: :create
  validate :quantity_fits_stock, on: :create
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
  # The variant's price when there is one: a negotiated offer still wins, since
  # price_cents on the order is what the two of them agreed.
  def unit_price_cents = price_cents.presence || variant&.price_cents_or_listing || listing.price_cents || 0
  def total_cents = unit_price_cents * (quantity.presence || 1).to_i
  def total_display = Shared::MoneyDisplay.format(total_cents, listing.currency || "NOK")

  def accept!
    raise "order cannot be accepted" unless open_offer?

    update!(status: "accepted")
    deliver_notification(buyer_record, title: I18n.t("marketplace.order_notification.offer_accepted"), body: I18n.t("marketplace.order_notification.offer_accepted_body", title: listing_title), source: self, kind: "order")
  end

  def decline!
    raise "order cannot be declined" unless open_offer?

    update!(status: "declined")
    deliver_notification(buyer_record, title: I18n.t("marketplace.order_notification.offer_declined"), body: I18n.t("marketplace.order_notification.offer_declined_body", title: listing_title), source: self, kind: "order")
  end

  def open_offer?
    status == "pending" && payment_status == "unpaid"
  end

  def mark_payment_pending!(provider:, reference:)
    raise "order is not payable" unless payable?

    update!(
      payment_provider: provider,
      payment_status: "pending",
      payment_reference: reference,
      status: "pending_payment"
    )
  end

  # One order becomes paid exactly once, and the guard for that has to be inside
  # the transaction.
  #
  # It was outside. The webhook controller asks `payable?` and then calls this,
  # so two deliveries of the same Stripe or Vipps event — which providers do
  # send — both read unpaid, both enter here, and both consume stock, notify
  # buyer and seller, and run partner attribution.
  #
  # The `.lock` below reads as protection and is not: on SQLite, Rails emits a
  # plain SELECT with no FOR UPDATE, so `Marketplace::Variant.lock.find_by`
  # locks nothing whatsoever. Checked rather than assumed —
  # `Marketplace::Variant.lock.to_sql` returns a bare SELECT.
  #
  # lock! is FOR UPDATE where the adapter has it and a reload where it does not,
  # and the reload is the half that matters here: SQLite serialises writers, so
  # by the time a second delivery holds the write transaction the first has
  # committed, and re-reading payment_status sees it.
  def mark_paid!(reference: payment_reference)
    transitioned = false
    transaction do
      lock!
      next if payment_status == "paid"

      transitioned = true
      # The variant is what was bought, so the variant is what runs out. Falling
      # back to the listing's own stock would let four sizes share one count,
      # which is the thing variants exist to stop.
      bought = variant_id ? Marketplace::Variant.lock.find_by(id: variant_id) : nil
      bought ||= listing_id && Marketplace::Listing.lock.find_by(id: listing_id)
      raise "listing is not in stock" if bought && !bought.in_stock?

      bought&.consume_stock!(quantity.presence || 1)
      update!(
        payment_status: "paid",
        payment_reference: reference.presence || payment_reference,
        paid_at: Time.current,
        status: "paid"
      )
    end
    # Everything below is a side effect of the transition, so it only runs when
    # this call is the one that made it. A replayed webhook used to send the
    # buyer a second "payment confirmed" and attribute the order to a partner
    # twice.
    return unless transitioned

    title = listing_title
    deliver_notification(seller, title: I18n.t("marketplace.order_notification.payment_received"), body: I18n.t("marketplace.order_notification.payment_received_body", title: title), source: self, kind: "order")
    deliver_notification(buyer_record, title: I18n.t("marketplace.order_notification.payment_confirmed"), body: I18n.t("marketplace.order_notification.payment_confirmed_body", title: title), source: self, kind: "order")
    PartnerMarketing.attribute_order!(self, visitor_digest: nil)
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

  # start! / find_payable_order. pending means a PSP session already exists —
  # starting another overwrote payment_reference and the first webhook missed.
  def startable?
    return false unless payment_status.in?(%w[unpaid failed])
    return false unless status.in?(%w[pending pending_payment])

    listed = association(:listing).loaded? ? listing : Marketplace::Listing.find_by(id: listing_id)
    listed.nil? || (listed.status == "active" && !listed.expired? && listed.in_stock?)
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
    deliver_notification(buyer_record, title: I18n.t("marketplace.order_notification.on_its_way"), body: detail, source: self, kind: "order")
  end

  # Returnable only against a shop. The right to send a purchase back is a right
  # against a business; a private sale between two people in the same city is
  # not one, and offering a control that the seller can refuse reads as a
  # promise the app cannot keep.
  def returnable_by?(user)
    return false unless user && user.id == buyer_id
    return false unless payment_status == "paid" && fulfilment_status == "delivered"
    return false if delivered_at.blank? || delivered_at < Marketplace::Return::WINDOW.ago
    return false if returns.open_returns.exists?

    Marketplace::Listing.where(id: listing_id).where.not(store_id: nil).exists?
  end

  # The item is back on the shelf, and the order says so. Called when the seller
  # confirms receipt, not when the return is approved: an approved return that
  # never arrives would put a thing back in stock that is still in the post.
  def enqueue_store_payout!
    store_id = Marketplace::Listing.where(id: listing_id).pick(:store_id)
    return if store_id.blank? || total_cents.to_i <= 0
    return if Marketplace::Payout.exists?(order_id: id)

    Marketplace::Payout.create!(
      store_id: store_id,
      order_id: id,
      amount_cents: total_cents,
      currency: payment_currency,
      status: "pending"
    )
  end

  def restock_returned!
    transaction do
      update!(fulfilment_status: "returned")
      back = variant_id ? Marketplace::Variant.find_by(id: variant_id) : Marketplace::Listing.find_by(id: listing_id)
      next if back.nil? || (back.respond_to?(:unlimited_stock?) ? back.unlimited_stock? : back.one_of_a_kind?)

      back.update_columns(stock: back.stock.to_i + (quantity.presence || 1).to_i, updated_at: Time.current)
    end
  end

  def mark_delivered!
    update!(fulfilment_status: "delivered", delivered_at: Time.current)
    enqueue_store_payout!
    deliver_notification(buyer_record, title: I18n.t("marketplace.order_notification.delivered"), body: listing_title, source: self, kind: "order")
  end

  private

  def listing_must_be_live
    return if listing.blank?
    return if listing.status == "active" && !listing.expired? && listing.in_stock?

    errors.add(:listing, :unavailable)
  end

  def variant_belongs_to_listing
    return if variant_id.blank?

    errors.add(:variant, :not_on_this_listing) unless Marketplace::Variant.exists?(id: variant_id, listing_id: listing_id)
  end

  # A listing that has sizes and an order that names none is an order the seller
  # cannot pack.
  def variant_chosen_when_the_listing_has_them
    return if variant_id.present? || listing_id.blank?

    errors.add(:variant, :blank) if Marketplace::Variant.exists?(listing_id: listing_id)
  end

  def quantity_fits_stock
    return if listing.blank? || listing.one_of_a_kind?

    qty = (quantity.presence || 1).to_i
    return if qty <= listing.available_quantity

    errors.add(:quantity, :exceeds_stock)
  end
end
