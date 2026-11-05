# frozen_string_literal: true

module Marketplace
  # What a buyer can know about a private seller before paying a stranger:
  # how long they have been here, how many sales they have completed, and
  # whether a Vipps or BankID login has proved who they are. A shop has its
  # own page and verification; this is for the person selling their bike.
  class SellerTrust
    def self.for(listing)
      return nil if listing.store_id.present?

      seller = User.strict_loading(false).find_by(id: listing.user_id)
      seller && new(seller)
    end

    attr_reader :seller

    def initialize(seller)
      @seller = seller
    end

    def member_since = seller.created_at.to_date

    # Sold and through: paid and delivered, or an offer the seller closed as
    # completed. An accepted offer that never changed hands is not a sale.
    def completed_sales
      sold = Marketplace::Order.joins(:listing).where(marketplace_listings: { user_id: seller.id })
      sold.where(status: "completed").or(sold.where(payment_status: "paid", fulfilment_status: "delivered")).count
    end

    def identity_verified? = seller.identity_verified?
  end
end
