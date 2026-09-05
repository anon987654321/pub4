# frozen_string_literal: true

class User
  module MarketplaceAssociations
    extend ActiveSupport::Concern

    included do
      has_many :marketplace_favorites, class_name: "Marketplace::ListingFavorite", dependent: :destroy
      has_many :marketplace_listings, class_name: "Marketplace::Listing", dependent: :destroy
      has_many :marketplace_stores, class_name: "Marketplace::Store", foreign_key: :owner_id, dependent: :destroy,
               inverse_of: :owner
      has_many :marketplace_orders, class_name: "Marketplace::Order", foreign_key: :buyer_id, dependent: :destroy,
               inverse_of: :buyer
      has_many :marketplace_saved_searches, class_name: "Marketplace::SavedSearch", dependent: :destroy
      has_many :marketplace_addresses, class_name: "Marketplace::Address", dependent: :destroy
      has_many :marketplace_checkouts, class_name: "Marketplace::Checkout", dependent: :destroy
    end
  end
end
