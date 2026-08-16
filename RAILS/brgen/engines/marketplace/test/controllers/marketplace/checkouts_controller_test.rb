# frozen_string_literal: true

require "test_helper"

# POST /checkout starts a real payment. It must require a session, reject an
# unknown provider, and — the money-safety property — fail CLOSED when the PSP is
# unconfigured: redirect back with the reason, never fake a success or 500. This
# controller had no test; StripeCheckout.start! raises NotConfigured without a key
# rather than pretending, and this pins that the controller honors it.
#
# Route helpers are marketplace.* — the mounted-engine proxy. They were written as
# marketplace_checkout_path when marketplace was a host `namespace`, and the split
# to engines/marketplace made every one of them a NameError. Nothing caught it:
# `bin/rails test` globs test/** from the app root, so engines/*/test never ran.
# Going through the proxy (rather than a literal "/checkout") also asserts the
# engine is still mounted where the host says it is.
class Marketplace::CheckoutsControllerTest < ActionDispatch::IntegrationTest
  setup do
    # A known apex (DomainRegistry) that is also a marketplace subdomain — the
    # controller 404s "Unknown host" otherwise, and .brgen.no scopes the session.
    host! "markedsplass.brgen.no"
    @buyer = User.create!(email_address: "co_buyer@example.com", password: "secret1234")
    @seller = User.create!(email_address: "co_seller@example.com", password: "secret1234")
    @category = Marketplace::Category.create!(name: "Probe", slug: "co-#{SecureRandom.hex(4)}")
    @listing = Marketplace::Listing.create!(title: "Checkout probe", price_cents: 2000,
                                            user: @seller, category: @category)
    @order = Marketplace::Order.create!(listing: @listing, buyer: @buyer)
  end

  def sign_in(user)
    post session_path, params: { email_address: user.email_address, password: "secret1234" }
  end

  test "create requires a session" do
    post marketplace.checkout_path, params: { provider: "stripe" }
    assert_response :redirect
    assert_no_match(/stripe\.com|vipps/, @response.redirect_url.to_s)
  end

  test "create rejects an unknown provider" do
    sign_in(@buyer)
    post marketplace.checkout_path, params: { provider: "bogus" }
    assert_redirected_to marketplace.cart_path
    assert_equal I18n.t("flash.marketplace.unknown_provider"), flash[:alert]
  end

  test "create fails closed when the provider is unconfigured" do
    sign_in(@buyer)
    assert_nil ENV["STRIPE_SECRET_KEY"]
    post marketplace.checkout_path, params: { provider: "stripe" }
    assert_redirected_to marketplace.cart_path
    assert_match(/stripe/i, flash[:alert].to_s)
    assert_equal "unpaid", @order.reload.payment_status
  end

  test "create reports an empty cart when nothing is payable" do
    sign_in(@buyer)
    @order.update!(payment_status: "paid", status: "paid")
    post marketplace.checkout_path, params: { provider: "stripe" }
    assert_redirected_to marketplace.cart_path
    assert_equal I18n.t("flash.marketplace.cart_not_payable"), flash[:alert]
  end

  test "create with a pending-payment order_id does not start a second session" do
    sign_in(@buyer)
    @order.update!(payment_status: "pending", status: "pending_payment", payment_reference: "cs_first")
    post marketplace.checkout_path, params: { provider: "stripe", order_id: @order.id }
    assert_redirected_to marketplace.cart_path
    assert_equal I18n.t("flash.marketplace.cart_not_payable"), flash[:alert]
    @order.reload
    assert_equal "pending", @order.payment_status
    assert_equal "cs_first", @order.payment_reference
  end

  test "create with a paid order_id does not rewind payment_status" do
    sign_in(@buyer)
    @order.update!(payment_status: "paid", status: "paid")
    post marketplace.checkout_path, params: { provider: "stripe", order_id: @order.id }
    assert_redirected_to marketplace.cart_path
    assert_equal I18n.t("flash.marketplace.cart_not_payable"), flash[:alert]
    @order.reload
    assert_equal "paid", @order.payment_status
    assert_equal "paid", @order.status
  end
end
