# frozen_string_literal: true

class Marketplace::ListingFavorite < ApplicationRecord
  belongs_to :user
  belongs_to :listing, class_name: "Marketplace::Listing"

  validates :user_id, uniqueness: { scope: :listing_id }
end
