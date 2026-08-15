# frozen_string_literal: true

# Last-click attribution, and the rules about who is allowed to earn.
#
# One entry point (`attribute_order!`) called from wherever an order becomes
# paid, so the rules live here instead of being re-derived at each call site. It
# is safe to call more than once for the same order: payment webhooks retry, and
# a retry must not pay a partner twice.
module PartnerMarketing
  Result = Data.define(:conversion, :reason) do
    def attributed? = !conversion.nil?
  end

  NOT_PAID = "order is not paid"
  NO_CLICK = "no live click for this visitor"
  SELF_REFERRAL = "partner is the buyer"
  MERCHANT_SELF = "partner owns the store"
  NOT_EARNING = "membership or programme is not active"
  ALREADY = "order already attributed"

  class << self
    # The visitor's live clicks, newest first. Last click wins, which is the
    # convention every network in this market settles on: it is the one a
    # partner can verify for themselves from their own link.
    def attribute_order!(order, visitor_digest:, now: Time.current)
      existing = Partner::Conversion.find_by(order_id: order.id)
      return Result.new(conversion: existing, reason: ALREADY) if existing
      return Result.new(conversion: nil, reason: NOT_PAID) unless order.payment_status == "paid"

      click = eligible_click(order, visitor_digest, now)
      return Result.new(conversion: nil, reason: NO_CLICK) unless click

      membership = click.membership
      if (refusal = refusal_for(membership, order))
        return Result.new(conversion: nil, reason: refusal)
      end

      Result.new(conversion: build_conversion!(order, click, membership, now), reason: nil)
    end

    private

    def eligible_click(order, visitor_digest, now)
      scope = Partner::Click.where(expires_at: now..).newest_first
      # listing_id is a column. order.listing&.store_id is a lazy read, and
      # mark_paid! is called from a PSP webhook that finds the order by id
      # under strict_loading_by_default — the same 500 that used to fire on
      # listing.user after payment had already committed.
      store_id = Marketplace::Listing.where(id: order.listing_id).pick(:store_id)
      if store_id
        scope = scope.joins(membership: :program).where(partner_programs: { store_id: store_id })
      end
      # The buyer's own account beats a cookie: a visitor who clicked a partner
      # link on their phone and bought on their laptop is the same sale.
      by_user = scope.where(user_id: order.buyer_id).first if order.buyer_id
      by_user || (visitor_digest.present? ? scope.find_by(visitor_digest: visitor_digest) : nil)
    end

    # Both of these are the same fraud in different clothes: someone earning a
    # commission on a sale they were always going to make. A merchant paying
    # themselves through their own partner account turns the programme into a
    # discount they book as marketing spend.
    def refusal_for(membership, order)
      return NOT_EARNING unless membership.earning?
      return SELF_REFERRAL if membership.user_id == order.buyer_id
      return MERCHANT_SELF if membership.user_id == order.seller&.id

      nil
    end

    def build_conversion!(order, click, membership, now)
      program = membership.program
      value = order_value_cents(order)

      Partner::Conversion.create!(
        membership: membership,
        click: click,
        order: order,
        status: "pending",
        order_value_cents: value,
        commission_cents: program.commission_for(value),
        currency: order.try(:currency).presence || "NOK",
        payable_after: now + program.hold_days.days
      )
    rescue ActiveRecord::RecordNotUnique
      # Two webhook deliveries raced past the find_by above. The unique index on
      # order_id is what actually enforces this; return the row that won.
      Partner::Conversion.find_by(order_id: order.id)
    end

    def order_value_cents(order)
      %i[total_cents amount_cents price_cents].each do |attribute|
        next unless order.respond_to?(attribute)

        value = order.public_send(attribute)
        return value.to_i if value.present?
      end
      0
    end
  end
end
