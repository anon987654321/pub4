# frozen_string_literal: true

module Marketplace
  # One row per price a listing actually carried, written by Listing's
  # create/update hooks. Nothing reads a single row; the only reader is
  # Listing#omnibus_reference_price_cents, which takes the trailing 30-day
  # minimum. The table exists so an anchor can never be rendered from a price
  # nobody observed — the persuasion_honesty source contract forbids the
  # alternative (a seller-entered or hardcoded "was" price).
  class ListingPriceObservation < ApplicationRecord
    self.table_name = "marketplace_listing_price_observations"

    belongs_to :listing, class_name: "Marketplace::Listing"

    validates :listing_id, presence: true
    validates :price_cents, numericality: { only_integer: true, greater_than: 0 }
    validates :observed_at, presence: true

    # The Omnibus window: prices applicable in the 30 days before a reduction.
    scope :trailing_30_days, ->(at = Time.current) {
      where(observed_at: (at - 30.days)..at)
    }
  end
end
