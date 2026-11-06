# frozen_string_literal: true

require "test_helper"

# VippsClient contract (APP_SPEC §5):
#
#   Mock mode (default): init never raises, points at /vipps/mock, marks the
#   payment authorised. sync_payment! is a no-op there — the mock approve
#   action owns capture.
#
#   Real mode (VIPPS_MOCK=0): documented ePayment v1 + Login calls. The HTTP
#   core (perform_request) is stubbed with path-keyed canned responses
#   (VippsHttpStubbing); everything above it — auth headers, token cache,
#   payload shape, state mapping, capture idempotency — runs for real.
#   Missing ENV raises NotAvailable before any HTTP happens.
class VippsClientTest < ActiveSupport::TestCase
  setup do
    @kitchen = seed_kitchen!
    @order = seed_order!(token: "tok-vipps-1")
    @order.update!(total_ore: 15800, vipps_order_id: nil, vipps_url: nil)
    vipps_reset_token_cache!
  end

  teardown do
    vipps_restore_http!
  end

  # --- Mock mode (the demo/dev contract) -------------------------------------

  test "mock init fills token, url and authorised without network" do
    assert VippsClient.mock_mode?

    assert VippsClient.init_payment(order: @order)
    assert_equal "mock-tok-vipps-1", @order.vipps_order_id
    assert_match %r{/vipps/mock\?token=tok-vipps-1\z}, @order.vipps_url
    assert_equal "authorised", @order.payment_state
  end

  test "mock sync_payment! is a no-op — the mock approve action owns capture" do
    @order.update!(payment_state: "authorised", vipps_order_id: "mock-tok-vipps-1")

    VippsClient.sync_payment!(order: @order)

    assert_equal "authorised", @order.reload.payment_state
  end

  test "mock capture is a no-op success" do
    assert VippsClient.capture_payment(order: @order)
  end

  # --- Real mode: wiring gaps fail loudly, before any HTTP --------------------

  test "real mode raises NotAvailable without credentials" do
    ENV["VIPPS_MOCK"] = "0"
    ENV.delete("VIPPS_CLIENT_ID")

    error = assert_raises(VippsClient::NotAvailable) do
      VippsClient.init_payment(order: @order)
    end
    assert_match(/VIPPS_CLIENT_ID/, error.message)
    assert_nil @order.reload.vipps_url, "a failed init must not leave a fake payment url"
  end

  # --- Real mode: the documented ePayment v1 flow ------------------------------

  test "real init creates the payment, stores reference and redirect" do
    vipps_real_mode!
    assert VippsClient.init_payment(order: @order)

    init = vipps_call_for("/epayment/v1/payments")
    assert_equal "mrdamascy-tok-vipps-1", init[:body_parsed]["reference"]
    assert_equal 15800, init[:body_parsed]["amount"]["value"]
    assert_equal "NOK", init[:body_parsed]["amount"]["currency"]
    assert_equal "WALLET", init[:body_parsed]["paymentMethod"]["type"]
    assert_equal "WEB_REDIRECT", init[:body_parsed]["userFlow"]
    assert_equal "4790000004", init[:body_parsed]["customer"]["phoneNumber"]
    assert_equal "mrdamascy-tok-vipps-1-init", init[:headers]["Idempotency-Key"]
    assert_equal "Bearer Tok1", init[:headers]["Authorization"]
    assert_equal "123456", init[:headers]["Merchant-Serial-Number"]

    assert_equal "mrdamascy-tok-vipps-1", @order.reload.vipps_order_id
    assert_equal "https://vipps.co/x1", @order.vipps_url
    assert_equal "pending", @order.payment_state, "real money is reserved only on AUTHORIZED"
  end

  test "real init without a known phone omits the customer block" do
    @order.update_column(:phone, "")  # defensive: no known phone on the order
    vipps_real_mode!
    VippsClient.init_payment(order: @order)

    assert_nil vipps_call_for("/epayment/v1/payments")[:body_parsed]["customer"]
  end

  test "access token is fetched once and cached across calls" do
    @order.update!(payment_state: "authorised", vipps_order_id: "mrdamascy-tok-vipps-1")
    vipps_real_mode!
    VippsClient.init_payment(order: @order)
    VippsClient.sync_payment!(order: @order)

    token_calls = vipps_calls.count { |c| c[:path] == "/accesstoken/get" }
    assert_equal 1, token_calls, "the token must be cached across calls"
  end

  test "sync captures on AUTHORIZED and confirms a placed order" do
    @order.update!(payment_state: "authorised", vipps_order_id: "mrdamascy-tok-vipps-1")
    vipps_real_mode!
    VippsClient.sync_payment!(order: @order)

    capture = vipps_call_for("/epayment/v1/payments/mrdamascy-tok-vipps-1/capture")
    assert_equal 15800, capture[:body_parsed]["modificationAmount"]["value"]
    assert_equal "mrdamascy-tok-vipps-1-capture", capture[:headers]["Idempotency-Key"]

    @order.reload
    assert_equal "captured", @order.payment_state
    assert_equal "confirmed", @order.state
  end

  test "sync capture never rewinds an order the kitchen already advanced" do
    @order.update!(payment_state: "authorised", vipps_order_id: "mrdamascy-tok-vipps-1",
                   state: "preparing")
    vipps_real_mode!
    VippsClient.sync_payment!(order: @order)

    @order.reload
    assert_equal "captured", @order.payment_state
    assert_equal "preparing", @order.state, "capture must not rewind the kitchen"
  end

  test "sync never captures a cancelled order and flags its reservation for staff" do
    @order.update!(payment_state: "pending", vipps_order_id: "mrdamascy-tok-vipps-1", state: "cancelled")
    vipps_real_mode!
    VippsClient.sync_payment!(order: @order)
    VippsClient.sync_payment!(order: @order)

    refute vipps_calls.any? { |c| c[:path].end_with?("/capture") }, "a cancelled order was captured"
    @order.reload
    assert_equal "authorised", @order.payment_state
    assert_equal "cancelled", @order.state
    assert_equal "manual_due", @order.refund_state
    assert_includes Order.refunds_due, @order
  end

  test "sync marks ABORTED and EXPIRED payments failed" do
    @order.update!(payment_state: "authorised", vipps_order_id: "mrdamascy-tok-vipps-1")

    vipps_real_mode!(remote_state: "ABORTED")
    VippsClient.sync_payment!(order: @order)
    assert_equal "failed", @order.reload.payment_state

    vipps_restore_http!
    vipps_reset_token_cache!
    vipps_real_mode!(remote_state: "EXPIRED")
    VippsClient.sync_payment!(order: @order)
    assert_equal "failed", @order.reload.payment_state
  end

  test "sync swallows transport errors — the poll must never 500 the page" do
    @order.update!(payment_state: "authorised", vipps_order_id: "mrdamascy-tok-vipps-1")

    ENV["VIPPS_MOCK"] = "0"
    ENV["VIPPS_CLIENT_ID"] = "vip-cid"
    ENV["VIPPS_CLIENT_SECRET"] = "vip-secret"
    ENV["VIPPS_SUBSCRIPTION_KEY"] = "vip-sub"
    ENV["VIPPS_MSN"] = "123456"
    sc = VippsClient.singleton_class
    sc.send(:alias_method, :orig_perform_request, :perform_request)
    sc.send(:define_method, :perform_request) do |*_args|
      raise VippsClient::NotAvailable, "Vipps API GET failed: HTTP 503"
    end

    assert_nothing_raised do
      VippsClient.sync_payment!(order: @order)
    end
    assert_equal "authorised", @order.reload.payment_state
  end

  test "capture on an already-captured order still converges" do
    @order.update!(payment_state: "captured", vipps_order_id: "mrdamascy-tok-vipps-1")
    vipps_real_mode!

    assert_nothing_raised do
      VippsClient.sync_payment!(order: @order)
    end
    assert_equal "captured", @order.reload.payment_state
  end

  # --- Login API ----------------------------------------------------------------

  test "login authorize URL carries client, scopes, state and redirect" do
    vipps_real_mode!
    url = VippsClient.login_authorize_url(
      redirect_uri: "https://mrdamascy.example/session/vipps/callback",
      state: "st-123", nonce: "n-123"
    )

    assert url.start_with?("https://api.vipps.no/access-management-1.0/access/oauth2/auth?")
    assert_includes url, "client_id=vip-cid"
    assert_includes url, "scope=openid+email+phoneNumber+address"
    assert_includes url, "state=st-123"
    assert_includes url, "response_type=code"
  end

  test "real login exchanges code and maps the userinfo profile" do
    vipps_real_mode!
    tokens = VippsClient.exchange_login_code!(
      code: "abc", redirect_uri: "https://mrdamascy.example/session/vipps/callback"
    )
    assert_equal "Tok1", tokens["access_token"]

    token_call = vipps_call_for("/access-management-1.0/access/oauth2/token")
    assert_match(/\Avip-cid:vip-secret\z/,
                 Base64.decode64(token_call[:headers]["Authorization"].split(" ").last))

    info = VippsClient.login_userinfo!(access_token: "Tok1")
    assert_equal "Ola Nordmann", info["name"]
    assert_equal "4790000004", info["phone_number"]
    assert_equal "Nygårdsgaten 12", info.dig("address", "street_address")
  end

  test "login phone normalisation keeps one identity per customer" do
    assert_equal "90000004", VippsClient.login_phone("4790000004")
    assert_equal "90000004", VippsClient.login_phone("90000004")
    assert_equal "90000004", VippsClient.login_phone("+47 900 00 004")
    assert_equal "4915123456789", VippsClient.login_phone("4915123456789")
    assert_nil VippsClient.login_phone("")
  end
end
