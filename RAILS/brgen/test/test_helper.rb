# frozen_string_literal: true

ENV["RAILS_ENV"] ||= "test"
require_relative "../config/environment"
require "rails/test_help"
require "shared/test_defaults"


module ActiveSupport
  class TestCase
    Shared::TestDefaults.install!(self)

    # 1x1 transparent PNG. Several models refuse to be valid without an
    # attachment — a dating profile may not be visible without a photo, and a
    # story may not exist without media — so building one is setup, not the
    # subject of any single test. Two test files had already written this
    # constant out for themselves.
    PIXEL_PNG = Base64.decode64(
      "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+M9QDwADhgGAWjR9awAAAABJRU5ErkJggg=="
    )

    def attach_pixel!(attachment, filename: "pixel.png")
      attachment.attach(io: StringIO.new(PIXEL_PNG), filename: filename, content_type: "image/png")
    end

    # Takeaway refuses an empty order at create — has_line_items and
    # meets_minimum_order both run on: :create — so an order has to be built
    # with its line items rather than filled in afterwards. Five test files
    # created bare orders and added items on the next line, which is the shape
    # the validation exists to reject.
    def build_takeaway_order(restaurant:, user:, item: nil, quantity: 1, **attrs)
      item ||= Takeaway::MenuItem.create!(
        restaurant: restaurant, name: "Dagens rett",
        price_cents: [restaurant.min_order_cents.to_i, 12_000].max, available: true
      )
      order = Takeaway::Order.new(
        { user: user, restaurant: restaurant, delivery_address: "Torget 1" }.merge(attrs)
      )
      order.order_items.build(menu_item: item, quantity: quantity, unit_price_cents: item.price_cents)
      order
    end

    def place_takeaway_order!(**kwargs)
      build_takeaway_order(**kwargs).tap(&:save!)
    end
  end
end
