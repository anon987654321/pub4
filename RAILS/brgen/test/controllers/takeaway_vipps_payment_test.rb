# frozen_string_literal: true

require "test_helper"
require "minitest/mock"

# Paying for takeaway with Vipps: the order page starts the payment, the
# webhook finds the order by its own reference kind and pays it once, and a
# kitchen cancelling a paid order sends the money back. Nothing reaches Vipps.
class TakeawayVippsPaymentTest < ActionDispatch::IntegrationTest
  setup do
    Brgen::CitySeed.sync! if City.table_exists?
    @city = City.find_by!(domain: "brgen.no")
    ActsAsTenant.current_tenant = @city
    @owner = create_user("tv_owner")
    @diner = create_user("tv_diner")
    @restaurant = Takeaway::Restaurant.create!(
      user: @owner, name: "Kjøkkenet #{SecureRandom.hex(2)}", address: "Torget 2",
      cuisine_type: "Norwegian", city: @city, active: true, min_order_cents: 0
    )
    @soup = Takeaway::MenuItem.create!(restaurant: @restaurant, name: "Fiskesuppe", price_cents: 18_900, available: true)
    @order = place_takeaway_order!(restaurant: @restaurant, user: @diner, item: @soup)
    @order.calculate_totals!
  end

  teardown { ActsAsTenant.current_tenant = nil }

  def create_user(name)
    User.strict_loading(false).create!(
      email_address: "#{name}_#{SecureRandom.hex(2)}@brgen.no", password: "password123",
      username: "#{name}_#{SecureRandom.hex(2)}", guest: false, city: @city
    )
  end

  def sign_in_as(user)
    host! "brgen.no"
    post session_path, params: { email_address: user.email_address, password: "password123" }
    host! "takeaway.brgen.no"
  end

  test "a takeaway reference names its own kind, not a marketplace order's" do
    assert_match(/\Abrgen-takeaway-#{@order.id}-\h{8}\z/, Marketplace::Payments::VippsCheckout.reference_for(@order))
  end

  test "the order page offers Vipps and the button hands the diner to Vipps" do
    sign_in_as(@diner)
    Marketplace::Payments::VippsCheckout.stub(:configured?, true) do
      get takeaway.order_path(@order)
    end
    assert_select "form[action='#{takeaway.pay_order_path(@order)}']"

    started = nil
    start = ->(order:, return_url:) { started = [ order.id, return_url ]; "https://landing.vipps.no/pay/1" }
    Marketplace::Payments::VippsCheckout.stub(:start!, start) do
      post takeaway.pay_order_path(@order)
    end

    assert_redirected_to "https://landing.vipps.no/pay/1"
    assert_equal @order.id, started.first
  end

  test "without Vipps keys the diner is told, and nothing starts" do
    sign_in_as(@diner)
    post takeaway.pay_order_path(@order)

    assert_redirected_to takeaway.order_path(@order)
    assert_equal I18n.t("flash.takeaway.payment_unavailable"), flash[:alert]
  end

  test "the webhook finds the takeaway order and pays it once" do
    reference = "brgen-takeaway-#{@order.id}-ab12cd34"
    @order.mark_payment_pending!(provider: "vipps", reference: reference)

    found = Webhooks::PaymentPaid.find_order_from_vipps_reference(reference)
    assert_equal @order, found
    2.times { Webhooks::PaymentPaid.mark_paid!(Webhooks::PaymentPaid.find_order_from_vipps_reference(reference), reference:) }

    assert_equal "paid", @order.reload.payment_status
    assert_equal 1, Notification.where(user_id: @owner.id, source_type: "Takeaway::Order", source_id: @order.id,
                                       title: I18n.t("takeaway.payment_received_title", id: @order.id)).count
  end

  test "a marketplace reference never resolves to a takeaway order" do
    assert_not_kind_of Takeaway::Order, Webhooks::PaymentPaid.find_order_from_vipps_reference("brgen-order-#{@order.id}-ab12cd34")
  end

  test "the kitchen cancelling a paid order returns the money through Vipps" do
    @order.update!(payment_status: "paid", payment_provider: "vipps", payment_reference: "brgen-takeaway-#{@order.id}-ff")
    keys = []
    Marketplace::Payments::VippsRefund.stub(:submit!, ->(order:, idempotency_key:) { keys << idempotency_key; "psp" }) do
      assert @order.cancel!
    end

    assert_equal "refunded", @order.reload.payment_status
    assert_equal [ "brgen-takeaway-#{@order.id}-cancel" ], keys
  end

  test "a paid order is not the diner's to cancel" do
    @order.update!(payment_status: "paid", payment_provider: "vipps")
    sign_in_as(@diner)

    patch takeaway.order_path(@order), params: { status: "cancelled" }

    assert_equal "pending", @order.reload.status
  end
end
