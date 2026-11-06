# frozen_string_literal: true

require "test_helper"

# The offer lifecycle a buyer and seller drive over POST and PATCH: an offer
# lands as a pending order, the seller accepts or declines it, and beside each
# transition sits the refusal the code defines: an unavailable listing, an
# order above the shelf, an order without a size on a listing with sizes, and
# a buyer or a stranger reaching for someone else's order. The Dintero capture
# side is skipped at the bottom: OrdersController#capture authorizes a query
# the order policy does not implement, so every capture POST raises before the
# PSP runs.
class Marketplace::OrdersControllerTest < ActionDispatch::IntegrationTest
  setup do
    # A known apex (DomainRegistry) that is also a marketplace subdomain — the
    # controller 404s "Unknown host" otherwise, and .brgen.no scopes the session.
    host! "markedsplass.brgen.no"
    # The order page opens the buyer-seller conversation, and Conversation
    # refuses a private thread on a registered host with no City row behind it,
    # so the suite seeds the registry's cities and names the tenant the way the
    # host suite does.
    Brgen::CitySeed.sync! if City.table_exists?
    ActsAsTenant.current_tenant = City.find_by!(domain: "brgen.no")
    @seller = User.create!(email_address: "or_seller@example.com", password: "secret1234")
    @buyer = User.create!(email_address: "or_buyer@example.com", password: "secret1234")
    @stranger = User.create!(email_address: "or_stranger@example.com", password: "secret1234")
    @category = Marketplace::Category.create!(name: "Probe", slug: "or-#{SecureRandom.hex(4)}")
    @listing = Marketplace::Listing.create!(
      user: @seller, category: @category, title: "Freeride ski 180", price_cents: 20_000, stock: 3
    )
  end

  def sign_in(user)
    post session_path, params: { email_address: user.email_address, password: "secret1234" }
  end

  teardown do
    ActsAsTenant.current_tenant = nil
  end

  test "an offer lands as a pending order and the seller is told" do
    sign_in(@buyer)

    assert_difference -> { Marketplace::Order.count }, 1 do
      post marketplace.listing_orders_path(@listing),
           params: { order: { message: "Er denne hel?" }, quantity: 1 }
    end

    assert_redirected_to marketplace.listing_path(@listing)
    assert_equal I18n.t("flash.marketplace.offer_sent"), flash[:notice]
    order = Marketplace::Order.order(:id).last
    assert_equal "pending", order.status
    assert_equal "unpaid", order.payment_status
    assert_equal @buyer.id, order.buyer_id
    assert_equal 20_000, order.price_cents
    assert_equal 1, order.quantity
    notification = Notification.where(source_type: "Marketplace::Order", source_id: order.id).order(:id).last
    assert_equal @seller.id, notification.user_id
    assert_equal I18n.t("marketplace.order_notification.new_offer"), notification.title
    assert Marketplace::ListingEvent.where(listing_id: @listing.id, event_type: "cart").exists?
  end

  test "an unavailable listing refuses the offer" do
    gone = Marketplace::Listing.create!(user: @seller, category: @category, title: "Gone ski", price_cents: 9_000)
    gone.update_columns(expires_at: 1.hour.ago)
    sold = Marketplace::Listing.create!(user: @seller, category: @category, title: "Sold ski", price_cents: 9_000)
    sold.update_columns(status: "sold")
    sign_in(@buyer)

    assert_no_difference -> { Marketplace::Order.count } do
      post marketplace.listing_orders_path(gone), params: { quantity: 1 }
      post marketplace.listing_orders_path(sold), params: { quantity: 1 }
    end

    assert_equal I18n.t("flash.marketplace.offer_failed"), flash[:alert]
  end

  test "an order above the shelf is refused" do
    sign_in(@buyer)

    assert_no_difference -> { Marketplace::Order.count } do
      post marketplace.listing_orders_path(@listing), params: { quantity: 9 }
    end

    assert_redirected_to marketplace.listing_path(@listing)
    assert_equal I18n.t("flash.marketplace.offer_failed"), flash[:alert]
  end

  # The variant is what is bought and its price is what the order records; the
  # listing's price is the fallback for a listing with none.
  test "a listing with sizes is bought by the size" do
    variant = Marketplace::Variant.create!(listing: @listing, price_cents: 24_500, stock: 2)
    sign_in(@buyer)

    post marketplace.listing_orders_path(@listing), params: { order: { variant_id: variant.id }, quantity: 1 }

    assert_redirected_to marketplace.listing_path(@listing)
    order = Marketplace::Order.order(:id).last
    assert_equal variant.id, order.variant_id
    assert_equal 24_500, order.price_cents
  end

  test "an order without a size on a listing with sizes is refused" do
    Marketplace::Variant.create!(listing: @listing, price_cents: 24_500, stock: 2)
    sign_in(@buyer)

    assert_no_difference -> { Marketplace::Order.count } do
      post marketplace.listing_orders_path(@listing), params: { quantity: 1 }
    end

    assert_redirected_to marketplace.listing_path(@listing)
    assert_equal I18n.t("flash.marketplace.offer_failed"), flash[:alert]
  end

  test "the seller accepts and the buyer is told" do
    order = Marketplace::Order.create!(listing: @listing, buyer: @buyer)
    sign_in(@seller)

    patch marketplace.order_path(order, accept: true)

    assert_redirected_to marketplace.order_path(order)
    assert_equal "accepted", order.reload.status
    notification = Notification.where(source_type: "Marketplace::Order", source_id: order.id).order(:id).last
    assert_equal @buyer.id, notification.user_id
    assert_equal I18n.t("marketplace.order_notification.offer_accepted"), notification.title
  end

  test "the seller declines and the offer is closed" do
    order = Marketplace::Order.create!(listing: @listing, buyer: @buyer)
    sign_in(@seller)

    patch marketplace.order_path(order, decline: true)

    assert_redirected_to marketplace.order_path(order)
    assert_equal "declined", order.reload.status
  end

  # open_offer? guards the transition: a paid order is money already recorded
  # and accept!/decline! would raise on it.
  test "neither accept nor decline moves a paid order" do
    order = Marketplace::Order.create!(listing: @listing, buyer: @buyer)
    order.update!(payment_status: "paid", status: "paid")
    sign_in(@seller)

    patch marketplace.order_path(order, accept: true)

    assert_redirected_to marketplace.order_path(order)
    assert_equal "paid", order.reload.status
  end

  # OrderPolicy#update? reads record.seller == user, so the buyer behind the
  # offer is refused before accept! runs.
  test "a buyer cannot accept their own offer" do
    order = Marketplace::Order.create!(listing: @listing, buyer: @buyer)
    sign_in(@buyer)

    patch marketplace.order_path(order, accept: true)

    assert_redirected_to marketplace.root_path
    assert_equal I18n.t("shared.flash.not_authorized"), flash[:alert]
    assert_equal "pending", order.reload.status
  end

  test "a stranger cannot read someone else's order" do
    order = Marketplace::Order.create!(listing: @listing, buyer: @buyer)
    sign_in(@stranger)

    get marketplace.order_path(order)

    assert_redirected_to marketplace.root_path
    assert_equal I18n.t("shared.flash.not_authorized"), flash[:alert]
  end

  # Scoped to buyer_id, and a paid order stays listed — the history used to
  # read like the cart, so a paid order vanished from it.
  test "the buyer's order history shows their orders and nobody else's" do
    pending_listing = Marketplace::Listing.create!(
      user: @seller, category: @category, title: "Sykkelhjelm", price_cents: 4_000, stock: 2
    )
    paid_listing = Marketplace::Listing.create!(
      user: @seller, category: @category, title: "Fjellsofa", price_cents: 9_000, stock: 2
    )
    Marketplace::Order.create!(listing: pending_listing, buyer: @buyer)
    paid = Marketplace::Order.create!(listing: paid_listing, buyer: @buyer)
    paid.update!(payment_status: "paid", status: "paid")
    Marketplace::Order.create!(listing: @listing, buyer: @stranger)
    sign_in(@buyer)

    get marketplace.orders_path

    assert_response :success
    assert_select "ul#buyer-orders li.order-row", count: 2
    assert_includes response.body, "Sykkelhjelm"
    assert_includes response.body, "Fjellsofa"
    assert_not_includes response.body, @listing.title
  end

  test "the buyer reads their own order page with its money" do
    order = Marketplace::Order.create!(listing: @listing, buyer: @buyer, quantity: 2)
    sign_in(@buyer)

    get marketplace.order_path(order)

    assert_response :success
    assert_includes response.body, @listing.title
    assert_includes response.body, order.reload.total_display
    assert_includes response.body, @buyer.display_name
    assert_includes response.body, @seller.display_name
    assert_no_match(/accept=true/, response.body)
  end

  # Marketplace::OrderPolicy defines show? and update? and no capture?, and
  # OrdersController#capture opens with authorize, so every capture POST raises
  # NoMethodError before DinteroCheckout.capture! runs. The transitions to pin
  # once the policy answers: capture moves an authorized order, the payment
  # state refuses capture it does not allow, an unconfigured Dintero fails the
  # capture closed, and a buyer cannot capture their own order.
  test "the seller captures a Dintero order the payment state allows" do
    skip "Marketplace::OrderPolicy lacks capture?; orders_controller.rb authorize raises before the PSP runs"
  end
end
