# frozen_string_literal: true

class User
  module TakeawayAssociations
    extend ActiveSupport::Concern

    included do
      has_many :takeaway_favorite_restaurants, class_name: "Takeaway::FavoriteRestaurant", dependent: :destroy
      has_many :takeaway_orders, class_name: "Takeaway::Order", dependent: :destroy
      has_many :takeaway_restaurants, class_name: "Takeaway::Restaurant", dependent: :destroy
    end
  end
end