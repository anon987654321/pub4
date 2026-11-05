# frozen_string_literal: true

require "test_helper"
require "minitest/mock"

# The parcel after payment: the seller says it has gone and that it arrived,
# the buyer confirms it did, and only the confirmation (or the window closing
# without one) creates a shop's payout. An accepted offer is paid from its own
# order page.
class Marketplace::OrderFulfilmentTest < ActionDispatch::IntegrationTest
  setup do
    host! "markedsplass.brgen.no"
    Brgen::CitySeed.sync! if City.table_exists?
    ActsAsTenant.current_tenant = City.find_by!(domain: "brgen.no")
    @seller = User.create!(email_address: "ff_seller_#{SecureRandom.hex(3)}@example.com", password: "secret1234")
    @buyer = User.create!(email_address: "ff_buyer_#{SecureRandom.hex(3)}@example.com", password: "secret1234")
    @category = Marketplace::Category.create!(name: "Probe", slug: "ff-#{SecureRandom.hex(4)}")
    @store = Marketplace::Store.create!(owner: @seller, name: "Butikk #{SecureRandom.hex(2)}", slug: "ff-#{SecureRandom.hex(4)}")
    @listing = Marketplace::Listing.create!(user: @seller, category: @category, store: @store,
                                            title: "Løpesko", price_cents: 120_000, stock: 4)
  end

  teardown { ActsAsTenant.current_tenant = nil }

  def sign_in(user)
    post session_path, params: { email_address: user.email_address, password: "secret1234" }
  end

  def page = Nokogiri::HTML(response.body)

  def paid_order
    order = @listing.orders.create!(buyer: @buyer, price_cents: @listing.price_cents, quantity: 1)
    order.update!(payment_status: "paid", status: "paid", payment_provider: "stripe", payment_reference: "cs_ff")
    order
  end

  test "the seller ships with a carrier and tracking code and the buyer is told" do
    order = paid_order
    sign_in(@seller)

    post marketplace.ship_order_path(order), params: { carrier: "Posten", tracking_code: "NO123" }

    assert_redirected_to marketplace.order_path(order)
    order.reload
    assert_equal "shipped", order.fulfilment_status
    assert_equal "Posten", order.carrier
    assert_equal "NO123", order.tracking_code
    assert Notification.exists?(user_id: @buyer.id, source_type: "Marketplace::Order", source_id: order.id,
                                title: I18n.t("marketplace.order_notification.on_its_way"))
  end

  test "the seller marking it delivered creates no payout; the buyer's confirmation does" do
    order = paid_order
    order.ship!(carrier: "Posten", tracking_code: "NO123")
    sign_in(@seller)

    assert_no_difference -> { Marketplace::Payout.count } do
      post marketplace.deliver_order_path(order)
    end
    assert_equal "delivered", order.reload.fulfilment_status
    assert_nil order.receipt_confirmed_at

    # The seller cannot confirm on the buyer's behalf.
    post marketplace.confirm_receipt_order_path(order)
    assert_nil order.reload.receipt_confirmed_at

    sign_in(@buyer)
    get marketplace.order_path(order)
    refute_nil page.at_css("form[action='#{marketplace.confirm_receipt_order_path(order)}']"), "the buyer has no way to confirm"

    assert_difference -> { Marketplace::Payout.count }, 1 do
      post marketplace.confirm_receipt_order_path(order)
    end
    assert order.reload.receipt_confirmed_at
    assert Notification.exists?(user_id: @seller.id, source_type: "Marketplace::Order", source_id: order.id,
                                title: I18n.t("marketplace.order_notification.receipt_confirmed"))
    assert_no_difference -> { Marketplace::Payout.count } do
      post marketplace.confirm_receipt_order_path(order)
    end
  end

  test "the buyer cannot ship or mark their own order delivered" do
    order = paid_order
    sign_in(@buyer)

    post marketplace.ship_order_path(order), params: { tracking_code: "X" }
    post marketplace.deliver_order_path(order)

    assert_equal "unfulfilled", order.reload.fulfilment_status
  end

  test "an unpaid order cannot be shipped" do
    order = @listing.orders.create!(buyer: @buyer, price_cents: @listing.price_cents, quantity: 1)
    sign_in(@seller)

    post marketplace.deliver_order_path(order)

    assert_equal "unfulfilled", order.reload.fulfilment_status
    assert_equal I18n.t("flash.marketplace.fulfilment_unavailable"), flash[:alert]
  end

  test "silence for the receipt window confirms receipt, unless a return is open" do
    quiet = paid_order
    quiet.report_delivered!
    disputed = paid_order
    disputed.report_delivered!
    disputed.returns.create!(reason: "Feil størrelse")
    recent = paid_order
    recent.report_delivered!
    [ quiet, disputed ].each { _1.update_columns(delivered_at: (Marketplace::Order::RECEIPT_WINDOW + 1.day).ago) }

    assert_difference -> { Marketplace::Payout.count }, 1 do
      Marketplace::ConfirmReceiptJob.perform_now
    end
    assert quiet.reload.receipt_confirmed_at
    assert_nil disputed.reload.receipt_confirmed_at
    assert_nil recent.reload.receipt_confirmed_at
  end

  test "an accepted offer can be paid from its order page" do
    offer = @listing.orders.create!(buyer: @buyer, quantity: 1, price_cents: 100_000)
    offer.accept!
    assert_predicate offer.reload, :startable?
    assert_predicate offer, :payable?

    sign_in(@buyer)
    Marketplace::Payments::VippsCheckout.stub(:configured?, true) do
      get marketplace.order_path(offer)
    end

    form = page.at_css("form[action='#{marketplace.checkout_path}']")
    refute_nil form, "an accepted offer offers no way to pay"
    assert_equal offer.id.to_s, form.at_css("input[name='order_id']")["value"]
    assert_equal "vipps", form.at_css("input[name='provider']")["value"]
  end
end
