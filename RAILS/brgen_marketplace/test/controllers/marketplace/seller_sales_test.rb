# frozen_string_literal: true

require "test_helper"

# The seller's side of the orders page: orders on their own listings, nobody
# else's, filterable by status, beside the buyer's own list.
class Marketplace::SellerSalesTest < ActionDispatch::IntegrationTest
  setup do
    host! "markedsplass.brgen.no"
    Brgen::CitySeed.sync! if City.table_exists?
    ActsAsTenant.current_tenant = City.find_by!(domain: "brgen.no")
    @seller = person("ss_seller")
    @buyer = person("ss_buyer")
    @category = Marketplace::Category.create!(name: "Salg", slug: "ss-#{SecureRandom.hex(4)}")
  end

  teardown { ActsAsTenant.current_tenant = nil }

  def person(prefix)
    User.create!(email_address: "#{prefix}_#{SecureRandom.hex(3)}@example.com", password: "secret1234")
  end

  def listing(owner, title) = @category.listings.create!(user: owner, title:, price_cents: 10_000, stock: 2)

  test "the sales list holds orders on the seller's listings only, and filters by status" do
    sold = listing(@seller, "Telemarkski").orders.create!(buyer: @buyer)
    paid = listing(@seller, "Sovepose").orders.create!(buyer: @buyer)
    paid.update!(payment_status: "paid", status: "paid")
    listing(@buyer, "Kjøperens sykkel").orders.create!(buyer: @seller)
    post session_path, params: { email_address: @seller.email_address, password: "secret1234" }

    get marketplace.orders_path(side: "sales")

    assert_response :success
    assert_select "nav a[aria-current=page][href=?]", marketplace.orders_path(side: "sales")
    assert_select "ul#seller-orders li.order-row", 2
    assert_select "ul#seller-orders a[href=?]", marketplace.order_path(sold)
    refute_includes response.body, "Kjøperens sykkel"

    get marketplace.orders_path(side: "sales", status: "paid")
    assert_select "ul#seller-orders li.order-row", 1
    assert_select "ul#seller-orders .order-status", I18n.t("marketplace.order_statuses.paid")
  end

  test "the purchases list links across to sales" do
    post session_path, params: { email_address: @buyer.email_address, password: "secret1234" }

    get marketplace.orders_path

    assert_select "nav a[href=?]", marketplace.orders_path(side: "sales"), text: I18n.t("marketplace.orders.sales_tab")
  end
end
