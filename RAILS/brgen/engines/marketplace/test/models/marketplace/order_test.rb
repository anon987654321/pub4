# frozen_string_literal: true

require "test_helper"

class Marketplace::OrderTest < ActiveSupport::TestCase
  setup do
    Brgen::CitySeed.sync! if City.table_exists?
    @city = City.find_by!(domain: "brgen.no")
    @seller = User.strict_loading(false).create!(email_address: "seller@brgen.no", password: "password123", city: @city)
    @buyer = User.strict_loading(false).create!(email_address: "buyer@brgen.no", password: "password123", city: @city)
    @category = Marketplace::Category.find_or_create_by!(name: "Test category", slug: "test-category-#{SecureRandom.hex(4)}")
  end

  teardown do
    ActsAsTenant.current_tenant = nil
  end

  test "accept transitions pending to accepted" do
    ActsAsTenant.with_tenant(@city) do
      listing = Marketplace::Listing.create!(user: @seller, category: @category, title: "Jacket", price_cents: 12_000, currency: "NOK")
      order = Marketplace::Order.create!(buyer: @buyer, listing: listing, status: "pending")

      order.accept!

      assert_equal "accepted", order.reload.status
    end
  end

  test "decline transitions pending to declined" do
    ActsAsTenant.with_tenant(@city) do
      listing = Marketplace::Listing.create!(user: @seller, category: @category, title: "Boots", price_cents: 8_000, currency: "NOK")
      order = Marketplace::Order.create!(buyer: @buyer, listing: listing, status: "pending")

      order.decline!

      assert_equal "declined", order.reload.status
    end
  end

  # The two tests above passed only because the order was built with the listing
  # already in memory. A PSP webhook finds the order by id, so nothing is
  # preloaded — and every model here is strict_loading by default (shared
  # ApplicationRecord), with production raising on a violation. mark_paid! then
  # raised on listing.user *after* update! had committed payment_status=paid:
  # payment recorded, seller and buyer never notified, 500 returned to Stripe,
  # and the retry skipped the work because the order was no longer payable?.
  #
  # Loading with a bare find_by is the whole point of these three.
  test "mark_paid! on a freshly-found order does not violate strict loading" do
    ActsAsTenant.with_tenant(@city) do
      listing = Marketplace::Listing.create!(user: @seller, category: @category, title: "Lamp", price_cents: 4_000, currency: "NOK")
      created = Marketplace::Order.create!(buyer: @buyer, listing: listing, status: "pending", payment_reference: "ref_strict")

      bare = Marketplace::Order.find_by(id: created.id)
      refute bare.association(:listing).loaded?, "guard: association must NOT be preloaded or this test proves nothing"

      bare.mark_paid!(reference: "ref_strict")

      assert_equal "paid", created.reload.payment_status
      assert_equal "paid", created.status
      assert_not_nil created.paid_at
    end
  end

  test "seller resolves on a freshly-found order and on the preloaded fast path" do
    ActsAsTenant.with_tenant(@city) do
      listing = Marketplace::Listing.create!(user: @seller, category: @category, title: "Desk", price_cents: 6_000, currency: "NOK")
      created = Marketplace::Order.create!(buyer: @buyer, listing: listing, status: "pending")

      assert_equal @seller.id, Marketplace::Order.find_by(id: created.id).seller&.id
      preloaded = Marketplace::Order.includes(listing: :user).find_by(id: created.id)
      assert_equal @seller.id, preloaded.seller&.id
    end
  end

  test "accept! and decline! work on a freshly-found order" do
    ActsAsTenant.with_tenant(@city) do
      listing = Marketplace::Listing.create!(user: @seller, category: @category, title: "Chair", price_cents: 3_000, currency: "NOK")
      accepted = Marketplace::Order.create!(buyer: @buyer, listing: listing, status: "pending")
      declined = Marketplace::Order.create!(buyer: @buyer, listing: listing, status: "pending")

      Marketplace::Order.find_by(id: accepted.id).accept!
      Marketplace::Order.find_by(id: declined.id).decline!

      assert_equal "accepted", accepted.reload.status
      assert_equal "declined", declined.reload.status
    end
  end
end
