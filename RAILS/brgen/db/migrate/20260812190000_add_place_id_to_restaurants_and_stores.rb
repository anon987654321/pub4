# frozen_string_literal: true

class AddPlaceIdToRestaurantsAndStores < ActiveRecord::Migration[8.1]
  def change
    add_reference :takeaway_restaurants, :place, foreign_key: true
    add_reference :marketplace_stores, :place, foreign_key: true
  end
end
