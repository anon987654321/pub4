# frozen_string_literal: true

require "test_helper"
require "minitest/mock"

class MarketplacePayoutTest < ActiveSupport::TestCase
  setup do
    Brgen::CitySeed.sync! if City.table_exists?
    @city = City.find_by!(domain: "brgen.no")
    ActsAsTenant.current_tenant = @city
    @seller = User.strict_loading(false).create!(
      email_address: "pay_seller@brgen.no", password: "password123", username: "pay_seller", guest: false
    )
    @buyer = User.strict_loading(false).create!(
      email_address: "pay_buyer@brgen.no", password: "password123", username: "pay_buyer", guest: false
    )
    @category = Marketplace::Category.create!(name: "Sko", slug: "sko-#{SecureRandom.hex(4)}")
    @store = Marketplace::Store.create!(owner: @seller, name: "Butikken #{SecureRandom.hex(2)}", slug: "butikk-#{SecureRandom.hex(4)}")
    @listing = Marketplace::Listing.create!(user: @seller, category: @category, store: @store,
                                            title: "Løpesko #{SecureRandom.hex(2)}", price_cents: 120_000, stock: 4)
  end

  teardown { ActsAsTenant.current_tenant = nil }

  def paid_order
    order = @listing.orders.create!(buyer: @buyer, price_cents: @listing.price_cents, quantity: 1)
    order.update!(payment_status: "paid", status: "paid", payment_provider: "stripe", payment_reference: "cs_test_1")
    order
  end

  test "paying a shop order does not enqueue a payout" do
    order = @listing.orders.create!(buyer: @buyer, price_cents: @listing.price_cents, quantity: 1)
    assert_no_difference -> { Marketplace::Payout.count } do
      order.mark_paid!(reference: "cs_test_1")
    end
  end


  test "delivering a Dintero order does not create a legacy payout" do
    order = @listing.orders.create!(
      buyer: @buyer,
      price_cents: @listing.price_cents,
      quantity: 1
    )
    order.update!(
      payment_status: "paid",
      status: "paid",
      payment_provider: "dintero",
      payment_reference: "brgen-dintero-order-1"
    )

    assert_no_difference -> { Marketplace::Payout.count } do
      order.mark_delivered!
    end
  end

  test "shipping and delivery record private lifecycle events" do
    order = paid_order
    assert_difference -> { ActivityEvent.where(event_name: "MarketplaceOrderShipped").count }, 1 do
      order.ship!(tracking_code: "NO123", carrier: "Test")
    end
    assert_difference -> { ActivityEvent.where(event_name: "MarketplaceOrderDelivered").count }, 1 do
      order.mark_delivered!
    end
    assert_equal "private", ActivityEvent.where(subject_type: "Marketplace::Listing", subject_id: @listing.id,
                                                 event_name: "MarketplaceOrderShipped").last.visibility
  end
  test "repeated shipment and delivery calls do not duplicate lifecycle events" do
    order = paid_order

    order.ship!(tracking_code: "NO123", carrier: "Test")
    order.ship!(tracking_code: "NO124", carrier: "Test")
    order.mark_delivered!
    order.mark_delivered!

    assert_equal 1, ActivityEvent.where(subject_type: "Marketplace::Listing", subject_id: @listing.id,
                                       event_name: "MarketplaceOrderShipped").count
    assert_equal 1, ActivityEvent.where(subject_type: "Marketplace::Listing", subject_id: @listing.id,
                                       event_name: "MarketplaceOrderDelivered").count
    assert_equal 1, Notification.where(
      source_type: "Marketplace::Order",
      source_id: order.id,
      title: I18n.t("marketplace.order_notification.on_its_way")
    ).count
    assert_equal 1, Notification.where(
      source_type: "Marketplace::Order",
      source_id: order.id,
      title: I18n.t("marketplace.order_notification.delivered")
    ).count
  end
  test "delivery of a shop order enqueues one pending payout" do
    order = paid_order
    assert_difference -> { Marketplace::Payout.count }, 1 do
      order.mark_delivered!
    end
    payout = Marketplace::Payout.find_by!(order_id: order.id)
    assert_equal "pending", payout.status
    assert_equal 120_000, payout.amount_cents
    assert_not payout.releasable?, "the return window is still open"
    assert_no_difference -> { Marketplace::Payout.count } do
      order.enqueue_store_payout!
    end
  end

  test "release! without Stripe stays pending, never sent" do
    order = paid_order
    order.update!(delivered_at: 15.days.ago, fulfilment_status: "delivered")
    @store.update!(stripe_connect_id: "acct_123ABC")
    order.enqueue_store_payout!
    payout = Marketplace::Payout.find_by!(order_id: order.id)
    assert payout.releasable?

    ENV.delete("STRIPE_SECRET_KEY")
    assert_raises(Marketplace::Payments::NotConfigured) { payout.release! }
    assert_equal "pending", payout.reload.status
    assert_nil payout.stripe_transfer_id
  end

  test "a received return voids a pending payout and does not mark refunded without Stripe" do
    order = paid_order
    order.mark_delivered!
    sent_back = order.returns.create!(reason: "For små")
    sent_back.receive!(by: @seller)

    assert_not_predicate sent_back.reload, :refunded?
    assert_equal "blocked", Marketplace::Payout.find_by!(order_id: order.id).status
    assert_equal "paid", order.reload.payment_status
  end

  test "a received Stripe return marks the refund only after Stripe answers" do
    order = paid_order
    order.mark_delivered!
    ENV["STRIPE_SECRET_KEY"] = "sk_test_local"
    Marketplace::Payments::StripeRefund.stub(:submit!, "re_live") do
      sent_back = order.returns.create!(reason: "Feil farge")
      sent_back.receive!(by: @seller)
      assert_predicate sent_back.reload, :refunded?
      assert_equal "re_live", sent_back.refund_reference
      assert_equal "refunded", order.reload.payment_status
    end
  ensure
    ENV.delete("STRIPE_SECRET_KEY")
  end
end
