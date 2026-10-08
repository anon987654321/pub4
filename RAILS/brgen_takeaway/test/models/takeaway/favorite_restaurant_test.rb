# frozen_string_literal: true

require "test_helper"

class Takeaway::FavoriteRestaurantTest < ActiveSupport::TestCase
  setup do
    Brgen::CitySeed.sync! if City.table_exists?
    @city = City.find_by!(domain: "brgen.no")
    @owner = User.strict_loading(false).create!(email_address: "fav_kitchen@brgen.no",
                                                password: "password123", city: @city)
    @diner = User.strict_loading(false).create!(email_address: "fav_diner@brgen.no",
                                                password: "password123", city: @city)
    @restaurant = ActsAsTenant.with_tenant(@city) do
      Takeaway::Restaurant.create!(user: @owner, name: "Stamsted", address: "Nygårdsgaten 5",
                                   cuisine_type: "Norwegian", city: @city, active: true)
    end
  end

  teardown do
    ActsAsTenant.current_tenant = nil
  end

  test "a diner favourites a restaurant once" do
    Takeaway::FavoriteRestaurant.create!(user: @diner, restaurant: @restaurant)
    again = Takeaway::FavoriteRestaurant.new(user: @diner, restaurant: @restaurant)

    assert_not again.valid?
    assert again.errors.added?(:user_id, :taken, value: @diner.id)
    assert Takeaway::FavoriteRestaurant.new(user: @owner, restaurant: @restaurant).valid?
  end
end
