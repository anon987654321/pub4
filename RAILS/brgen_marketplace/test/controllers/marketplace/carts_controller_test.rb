# frozen_string_literal: true

require "test_helper"

# A pending order is a line in the buyer's cart. These tests cover the cart
# page, the quantity and withdraw edits on a line, the bulk seller re-notify,
# the ownership line on a cart line, and the checkout hand-off where the
# delivery-address gate sits. The configured payment paths themselves are
# Marketplace::CheckoutsControllerTest's subject.
class Marketplace::CartsControllerTest < ActionDispatch::IntegrationTest
  setup do
    # A known apex (DomainRegistry) that is also a marketplace subdomain — the
    # controller 404s "Unknown host" otherwise, and .brgen.no scopes the session.
    host! "markedsplass.brgen.no"
    @seller = User.create!(email_address: "ca_seller@example.com", password: "secret1234")
    @buyer = User.create!(email_address: "ca_buyer@example.com", password: "secret1234")
    @stranger = User.create!(email_address: "ca_stranger@example.com", password: "secret1234")
    @category = Marketplace::Category.create!(name: "Probe", slug: "ca-#{SecureRandom.hex(4)}")
    @listing = Marketplace::Listing.create!(
      user: @seller, category: @category, title: "Freeride ski 180", price_cents: 1_500, stock: 5
    )
    @item = Marketplace::Order.create!(listing: @listing, buyer: @buyer, quantity: 2)
  end

  def sign_in(user)
    post session_path, params: { email_address: user.email_address, password: "secret1234" }
  end

  test "the cart lists what is waiting and what it costs" do
    sign_in(@buyer)

    get marketplace.cart_path

    assert_response :success
    assert_includes response.body, @listing.title
    assert_includes response.body,
                    I18n.t("marketplace.cart_total", amount: Shared::MoneyDisplay.format(@item.total_cents))
    assert_select "form[action*='/cart/items/']"
  end

  # load_cart reads only Current.user's pending orders, so another buyer's
  # line never enters the page.
  test "the cart is the buyer's own" do
    sign_in(@stranger)

    get marketplace.cart_path

    assert_response :success
    assert_not_includes response.body, @listing.title
    assert_includes response.body, I18n.t("marketplace.cart_empty_title")
  end

  test "a line is counted up to what is on the shelf and no further" do
    sign_in(@buyer)

    patch marketplace.cart_item_path(@item), params: { quantity: 4 }

    assert_redirected_to marketplace.cart_path
    assert_equal I18n.t("marketplace.cart_quantity_updated"), flash[:notice]
    assert_equal 4, @item.reload.quantity

    patch marketplace.cart_item_path(@item), params: { quantity: 9 }

    assert_redirected_to marketplace.cart_path
    assert_equal I18n.t("marketplace.cart_quantity_refused", available: 5), flash[:alert]
    assert_equal 4, @item.reload.quantity
  end

  # Withdrawn, not deleted: the seller was told about the offer, and their side
  # keeps the row with its answer.
  test "a line left is declined and the cart empties" do
    sign_in(@buyer)

    delete marketplace.cart_item_path(@item)

    assert_redirected_to marketplace.cart_path
    assert_equal I18n.t("marketplace.cart_item_removed"), flash[:notice]
    assert_equal "declined", @item.reload.status

    get marketplace.cart_path
    assert_includes response.body, I18n.t("marketplace.cart_empty_title")
  end

  test "sending offers re-notifies every seller with a pending line" do
    sign_in(@buyer)

    assert_difference -> { Notification.count }, 1 do
      post marketplace.send_offers_cart_path
    end

    assert_redirected_to marketplace.cart_path
    assert_equal I18n.t("flash.marketplace.offers_sent", count: 1), flash[:notice]
    notification = Notification.where(source_type: "Marketplace::Order", source_id: @item.id).order(:id).last
    assert_equal @seller.id, notification.user_id
    assert_equal I18n.t("marketplace.order_notification.offer_reminder"), notification.title
  end

  test "sending offers with an empty cart says so" do
    @item.update!(status: "declined")
    sign_in(@buyer)

    post marketplace.send_offers_cart_path

    assert_redirected_to marketplace.cart_path
    assert_equal I18n.t("flash.marketplace.cart_empty"), flash[:alert]
  end

  # set_item finds inside Current.user's own orders, so another buyer's line
  # id reads as a missing record.
  test "someone else's cart line does not exist for you" do
    sign_in(@stranger)

    assert_raises(ActiveRecord::RecordNotFound) do
      patch marketplace.cart_item_path(@item), params: { quantity: 1 }
    end

    assert_raises(ActiveRecord::RecordNotFound) do
      delete marketplace.cart_item_path(@item)
    end
    assert_equal 2, @item.reload.quantity
  end

  # build_basket refuses before any Checkout row is written: a basket paid
  # without an address is a parcel with nowhere to go, discovered after the
  # money has moved.
  test "paying the basket asks for a delivery address first" do
    prior = ENV["STRIPE_SECRET_KEY"]
    ENV["STRIPE_SECRET_KEY"] = "sk_test_probe"
    sign_in(@buyer)

    assert_no_difference -> { Marketplace::Checkout.count } do
      post marketplace.checkout_path, params: { provider: "stripe" }
    end

    assert_redirected_to marketplace.addresses_path
    assert_equal I18n.t("flash.marketplace.address_needed"), flash[:alert]
  ensure
    prior ? ENV["STRIPE_SECRET_KEY"] = prior : ENV.delete("STRIPE_SECRET_KEY")
  end
end
