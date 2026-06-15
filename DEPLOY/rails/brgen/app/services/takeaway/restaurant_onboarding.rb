# frozen_string_literal: true
# AN621: Restaurant onboarding

module Takeaway
  class RestaurantOnboarding
    def initialize(owner)
      @owner = owner
    end

    def create_from_csv(file, attrs)
      restaurant = Restaurant.create!(attrs.merge(owner: @owner))
      CSV.foreach(file.path, headers: true) do |row|
        restaurant.menu_items.create!(name: row["name"], price_cents: row["price"].to_i * 100, dietary_tags: row["tags"])
      end
      restaurant
    end

    def set_delivery_zone(polygon)
      @owner.restaurants.last.update!(delivery_zone: polygon)
    end
  end
end