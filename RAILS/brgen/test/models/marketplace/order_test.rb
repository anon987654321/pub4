# frozen_string_literal: true

require "test_helper"

class Marketplace::OrderTest < ActiveSupport::TestCase
  setup do
    Brgen::CitySeed.sync! if City.table_exists?
    @city = City.find_by!(domain: "brgen.no")
    @seller = User.strict_loading(false).create!(email_address: "seller@brgen.no", password: "password123", city: @city)
    @buyer = User.strict_loading(false).create!(email_address: "buyer@brgen.no", password: "password123", city: @city)
  end

  teardown do
    ActsAsTenant.current_tenant = nil
  end

  test "accept transitions pending to accepted" do
    ActsAsTenant.with_tenant(@city) do
      listing = Marketplace::Listing.create!(user: @seller, title: "Jacket", price_cents: 12_000, currency: "NOK")
      order = Marketplace::Order.create!(buyer: @buyer, listing: listing, status: "pending")

      order.accept!

      assert_equal "accepted", order.reload.status
    end
  end

  test "decline transitions pending to declined" do
    ActsAsTenant.with_tenant(@city) do
      listing = Marketplace::Listing.create!(user: @seller, title: "Boots", price_cents: 8_000, currency: "NOK")
      order = Marketplace::Order.create!(buyer: @buyer, listing: listing, status: "pending")

      order.decline!

      assert_equal "declined", order.reload.status
    end
  end
end