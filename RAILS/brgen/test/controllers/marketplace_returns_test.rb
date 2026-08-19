# frozen_string_literal: true

require "test_helper"

# The right to send a purchase back is a right against a business, so a return
# is offered against a shop's listing and not against somebody selling their own
# bike.
class MarketplaceReturnsTest < ActionDispatch::IntegrationTest
  setup do
    Brgen::CitySeed.sync! if City.table_exists?
    @city = City.find_by!(domain: "brgen.no")
    @seller = create_user("mr_seller")
    @buyer = create_user("mr_buyer")
    ActsAsTenant.current_tenant = @city
    @category = Marketplace::Category.create!(name: "Sko", slug: "sko-#{SecureRandom.hex(4)}")
    @store = Marketplace::Store.create!(owner: @seller, name: "Butikken #{SecureRandom.hex(2)}", slug: "butikk-#{SecureRandom.hex(4)}")
    @shop_listing = Marketplace::Listing.create!(user: @seller, category: @category, store: @store,
                                                 title: "Løpesko #{SecureRandom.hex(2)}", price_cents: 120_000, stock: 4)
    @private_listing = Marketplace::Listing.create!(user: @seller, category: @category,
                                                    title: "Brukt sykkel #{SecureRandom.hex(2)}", price_cents: 200_000)
  end

  teardown { ActsAsTenant.current_tenant = nil }

  def create_user(name)
    User.strict_loading(false).create!(
      email_address: "#{name}@brgen.no", password: "password123", username: name, guest: false
    )
  end

  def sign_in_as(user)
    host! "brgen.no"
    post session_path, params: { email_address: user.email_address, password: "password123" }
    host! "markedsplass.brgen.no"
  end

  def delivered_order(listing, quantity: 1)
    order = listing.orders.create!(buyer: @buyer, price_cents: listing.price_cents, quantity: quantity)
    order.update!(payment_status: "paid", status: "paid", fulfilment_status: "delivered", delivered_at: 2.days.ago)
    order
  end

  test "a shop order is returnable and a private sale is not" do
    assert_predicate delivered_order(@shop_listing), :present?
    assert delivered_order(@shop_listing).returnable_by?(@buyer)
    assert_not delivered_order(@private_listing).returnable_by?(@buyer)
  end

  test "the window closes fourteen days after delivery" do
    order = delivered_order(@shop_listing)
    assert order.returnable_by?(@buyer)

    order.update!(delivered_at: 15.days.ago)
    assert_not order.reload.returnable_by?(@buyer)
  end

  test "the seller cannot request a return on their own sale" do
    assert_not delivered_order(@shop_listing).returnable_by?(@seller)
  end

  test "a buyer asks, the seller approves, and the stock comes back on receipt" do
    order = delivered_order(@shop_listing, quantity: 2)
    sign_in_as(@buyer)

    assert_difference -> { Marketplace::Return.count }, 1 do
      post marketplace.order_returns_path(order), params: { return: { reason: "For små" } }
    end
    sent_back = Marketplace::Return.order(:created_at).last
    assert Notification.where(user_id: @seller.id, kind: "order").exists?

    sign_in_as(@seller)
    patch marketplace.order_return_path(order, sent_back, decision: "approve")
    assert_equal "approved", sent_back.reload.status
    # Approval does not restock: the shoes are still in the post.
    assert_equal 4, @shop_listing.reload.stock

    patch marketplace.order_return_path(order, sent_back, decision: "receive")
    assert_equal "received", sent_back.reload.status
    assert_equal 6, @shop_listing.reload.stock
    assert_equal "returned", order.reload.fulfilment_status
  end

  # Nothing in the tree moves money yet, and the page says so rather than
  # implying the buyer has been paid.
  test "a received return is not a refunded one" do
    order = delivered_order(@shop_listing)
    sent_back = order.returns.create!(reason: "Feil farge")
    sent_back.receive!(by: @seller)

    assert_not_predicate sent_back.reload, :refunded?
  end

  test "one open return per order" do
    order = delivered_order(@shop_listing)
    order.returns.create!(reason: "Første")

    second = order.returns.new(reason: "Andre")
    assert_not second.valid?
    assert_not order.returnable_by?(@buyer)
  end

  test "only the seller decides" do
    order = delivered_order(@shop_listing)
    sent_back = order.returns.create!(reason: "For små")
    sign_in_as(@buyer)

    patch marketplace.order_return_path(order, sent_back, decision: "approve")
    assert_response :forbidden
    assert_equal "requested", sent_back.reload.status
  end
end
