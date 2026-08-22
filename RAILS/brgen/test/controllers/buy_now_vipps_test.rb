# frozen_string_literal: true

require "test_helper"
require "minitest/mock"

# The one-click lane: POST /checkout with listing_id creates the order and
# starts Vipps in the same request — the whole on-site purchase is one click.
# Stubbed at the provider boundary; the refusal paths run unstubbed because
# they are the honesty half (an unkeyed provider must refuse, not fake).
class BuyNowVippsTest < ActionDispatch::IntegrationTest
  setup do
    Brgen::CitySeed.sync! if City.table_exists?
    @city = City.find_by!(domain: "brgen.no")
    ActsAsTenant.current_tenant = @city
    @seller = User.create!(email_address: "sell-#{SecureRandom.hex(4)}@brgen.no",
                           password: "password12345", username: "sel_#{SecureRandom.hex(3)}", city: @city)
    @buyer = User.create!(email_address: "buy-#{SecureRandom.hex(4)}@brgen.no",
                          password: "password12345", username: "buy_#{SecureRandom.hex(3)}", city: @city,
                          email_verified_at: Time.current)
    category = Marketplace::Category.first ||
               Marketplace::Category.create!(name: "Diverse", slug: "diverse-#{SecureRandom.hex(3)}")
    @listing = Marketplace::Listing.create!(user: @seller, title: "Sykkel", description: "Fin bysykkel, lite brukt",
                                            price_cents: 150_000, status: "active", kind: "goods", category: category)
    host! "markedsplass.brgen.no"
    post main_app.session_path, params: { email_address: @buyer.email_address, password: "password12345" }
  end
  teardown { ActsAsTenant.current_tenant = nil }

  test "one click creates the order and redirects into Vipps" do
    Marketplace::Payments::VippsCheckout.stub(:configured?, true) do
      Marketplace::Payments::VippsCheckout.stub(:start!, "https://apitest.vipps.no/pay/abc") do
        assert_difference -> { @listing.orders.count }, 1 do
          post "/checkout", params: { provider: "vipps", listing_id: @listing.id }
        end
        assert_redirected_to "https://apitest.vipps.no/pay/abc", "got #{response.redirect_url.inspect} alert=#{flash[:alert].inspect}"
        order = Marketplace::Order.order(:id).last
        assert_equal @buyer.id, order.buyer_id
        assert_equal 150_000, order.price_cents
        assert_equal 1, order.quantity
      end
    end
  end

  test "an unkeyed Vipps refuses instead of faking — no order debris" do
    assert_no_difference -> { Marketplace::Order.count } do
      post "/checkout", params: { provider: "vipps", listing_id: @listing.id }
    end
    assert_response :redirect
  end

  test "a seller cannot one-click their own listing" do
    own = Marketplace::Listing.create!(user: @buyer, title: "Egen vare", description: "Selger min egen ting her",
                                       price_cents: 5_000, status: "active", kind: "goods",
                                       category: @listing.category)
    Marketplace::Payments::VippsCheckout.stub(:configured?, true) do
      assert_no_difference -> { Marketplace::Order.count }, -> { o = Marketplace::Order.order(:id).last; "debris: listing=#{o&.listing_id} own=#{own.id} buyer=#{o&.buyer_id} me=#{@buyer.id} alert=#{flash[:alert].inspect}" } do
        post "/checkout", params: { provider: "vipps", listing_id: own.id }
      end
    end
  end

  test "an expired listing refuses the click" do
    @listing.update!(expires_at: 1.day.ago)
    Marketplace::Payments::VippsCheckout.stub(:configured?, true) do
      assert_no_difference -> { Marketplace::Order.count } do
        post "/checkout", params: { provider: "vipps", listing_id: @listing.id }
      end
    end
  end
end
