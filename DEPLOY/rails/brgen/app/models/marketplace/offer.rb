# frozen_string_literal: true
# AN614: Price negotiation

module Marketplace
  class Offer < ApplicationRecord
    belongs_to :listing
    belongs_to :buyer, class_name: "User"
    belongs_to :seller, class_name: "User"

    enum :status, { pending: 0, countered: 1, accepted: 2, rejected: 3 }

    after_update_commit :lock_listing_if_accepted

    private

    def lock_listing_if_accepted
      listing.update!(status: "sold", sold_price_cents: amount_cents) if accepted?
    end
  end
end