# frozen_string_literal: true

class Marketplace::ListingFavorite < ApplicationRecord
  include Shared::ActivityTrackable
  tracks_activity created: "MarketplaceListingFavorited", source_vertical: "marketplace", visibility: "private", actor: :user

  belongs_to :user
  belongs_to :listing, class_name: "Marketplace::Listing"

  validates :user_id, uniqueness: { scope: :listing_id }
end
