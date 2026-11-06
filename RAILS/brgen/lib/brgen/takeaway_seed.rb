# frozen_string_literal: true

module Brgen
  # db/seeds.rb's takeaway step, kept whole: the restaurants, each menu in the
  # restaurant's own cuisine, orders and reviews, and the delivery drivers.
  # The caller sets the tenant; CityTenantable adds belongs_to :city, and the
  # string column :city is the display label only, not the association.
  module TakeawaySeed
    def self.seed!(users:, city:, scale:)
      restaurants = seed_restaurants(users, city.name, scale)
      restaurants.each { |restaurant| seed_menu(restaurant) }
      restaurants.sample(10).each { |restaurant| seed_order(restaurant, users.sample) }
      seed_drivers(users)
      restaurants
    end

    # Cuisine now travels with the restaurant name (PlausibleContent.restaurant_for).
    def self.seed_restaurants(users, city_label, scale)
      num_rest = (15 * scale).clamp(5, 100)
      num_rest.times.map do |i|
        # Faker::Restaurant.name is US-styled ("The Rusty Spoon") and the address was
        # a Faker street that doesn't exist in Bergen. Name and cuisine come from the
        # same pair so a place called "Ramen Bergen" isn't filed as Mexican.
        name, cuisine = Brgen::PlausibleContent.restaurant_for(i)
        Takeaway::Restaurant.create!(
          user: users.sample,
          name: name,
          cuisine_type: cuisine,
          address: Brgen::PlausibleContent.street_address,
          active: true, demo: true,
          delivery_fee_cents: rand(2000..6000),
          min_order_cents: rand(8000..15_000),
          latitude: 60.39 + rand(-0.04..0.04),
          longitude: 5.33 + rand(-0.04..0.04)
        ).tap { |restaurant| restaurant.update_column(:city, city_label) }
      end
    end

    def self.seed_menu(rest)
      # Menu now matches the restaurant's own cuisine, in Norwegian, rather than
      # Faker::Food's English dishes served at a Bergen kebab house.
      dishes = Brgen::PlausibleContent.dishes_for(rest.cuisine_type)
      dishes.sample(rand(4..dishes.size)).each do |(name, description)|
        Takeaway::MenuItem.create!(
          restaurant: rest,
          name: name,
          description: description,
          price_cents: rand(6000..18_000),
          available: true
        )
      end
    end

    # Orders + reviews
    #
    # Build the line items before saving, the way Takeaway::OrdersController#create
    # does. This used to create! the order bare and attach items afterwards, and
    # Takeaway::Order#meets_minimum_order reads `order_items.target` -- so the
    # subtotal was 0.00 at validation time and every restaurant with a
    # min_order_cents rejected its own seed order:
    #
    #   ActiveRecord::RecordInvalid: Minimum order for Døner Ekspress Åsane is
    #   122.76 NOK — your subtotal is 0.00 NOK.
    #
    # That took down `db:seed:replant`, which is a stage of vps_ci.sh, which is a
    # stage of vps-deploy -- so brgen could not be deployed at all, while the
    # validation itself is correct and the real checkout path was always fine.
    # Enough menu items to clear any threshold the restaurant advertises.
    def self.seed_order(rest, buyer)
      # includes(:restaurant) is load-bearing, not decoration: ApplicationRecord sets
      # strict_loading_by_default in every environment, and building an OrderItem
      # reads menu_item.restaurant, so dropping the preload raises
      # StrictLoadingViolationError here rather than degrading to an extra SELECT.
      menu = Takeaway::MenuItem.available.includes(:restaurant)
                               .where(restaurant: rest).order(Arel.sql("RANDOM()")).to_a
      return if menu.empty?

      order = Takeaway::Order.new(
        user: buyer,
        restaurant: rest,
        status: %w[pending out_for_delivery delivered].sample,
        delivery_address: Faker::Address.street_address,
        special_instructions: [ nil, Faker::Lorem.sentence ].sample
      )

      subtotal = 0
      minimum = rest.min_order_cents.to_i
      menu.each do |item|
        break if order.order_items.size >= 2 && subtotal >= minimum

        quantity = rand(1..2)
        order.order_items.build(menu_item: item, quantity: quantity, unit_price_cents: item.price_cents)
        subtotal += item.price_cents.to_i * quantity
      end
      # A restaurant whose whole menu cannot reach its own minimum is bad seed data,
      # not a reason to abort the seed.
      return if subtotal < minimum

      order.save!
      order.calculate_totals!
      order.record_activity!("TakeawayOrder") if order.respond_to?(:record_activity!)

      # Review
      return unless order.status == "delivered"

      Takeaway::Review.create!(
        user: buyer,
        restaurant: rest,
        order: order,
        rating: rand(3..5),
        body: Faker::Restaurant.review
      )
    end

    # Delivery drivers
    def self.seed_drivers(users)
      5.times do
        Takeaway::DeliveryDriver.create!(
          user: users.sample,
          vehicle_type: Takeaway::DeliveryDriver::VEHICLE_TYPES.sample,
          available: [ true, false ].sample,
          current_lat: 60.39 + rand(-0.03..0.03),
          current_lng: 5.33 + rand(-0.03..0.03)
        )
      end
    end

    private_class_method :seed_restaurants, :seed_menu, :seed_order, :seed_drivers
  end
end
