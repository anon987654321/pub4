# frozen_string_literal: true

class Takeaway::FavoriteRestaurant < ApplicationRecord
  belongs_to :user
  belongs_to :restaurant, class_name: "Takeaway::Restaurant"

  validates :user_id, uniqueness: { scope: :restaurant_id }
end
