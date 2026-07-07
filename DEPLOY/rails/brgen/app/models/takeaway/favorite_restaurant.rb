# frozen_string_literal: true

class Takeaway::FavoriteRestaurant < ApplicationRecord
  include Shared::ActivityTrackable
  tracks_activity created: "TakeawayRestaurantFavorited", source_vertical: "takeaway", visibility: "private", actor: :user

  belongs_to :user
  belongs_to :restaurant, class_name: "Takeaway::Restaurant"

  validates :user_id, uniqueness: { scope: :restaurant_id }
end
