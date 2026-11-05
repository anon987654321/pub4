# frozen_string_literal: true

require "test_helper"

# The real Vipps webhook (POST /vipps/callback): Vipps carries the shared
# webhook secret in the Authorization header and posts payment events
# [{reference:, state:, …}]. Contract here: unauthenticated → 401, verified
# events drive sync_payment! (capture on AUTHORIZED), replays converge,
# garbage JSON → 400, unknown references are ignored politely.
class VippsCallbackTest < ActionDispatch::IntegrationTest
  setup do
    @kitchen = seed_kitchen!
    @order = seed_order!(token: "tok-hook-1")
    @order.update!(payment_state: "authorised", vipps_order_id: "mrdamascy-tok-hook-1")
  end

  teardown do
    vipps_restore_http!
    ENV.delete("VIPPS_WEBHOOK_SECRET")
  end

  test "answers 401 without a webhook secret" do
    post vipps_callback_path, headers: { "Content-Type" => "application/json" },
                              body: [].to_json

    assert_response :unauthorized
    assert_equal "authorised", @order.reload.payment_state
  end

  test "answers 401 with a wrong secret" do
    ENV["VIPPS_WEBHOOK_SECRET"] = "sekret"
    post vipps_callback_path, headers: { "Content-Type" => "application/json",
                                                     "Authorization" => "nope" },
                              body: [].to_json

    assert_response :unauthorized
  end

  test "AUTHORIZED event captures and confirms the order" do
    ENV["VIPPS_WEBHOOK_SECRET"] = "sekret"
    vipps_real_mode!

    post vipps_callback_path,
         headers: { "Content-Type" => "application/json", "Authorization" => "sekret" },
         body: [ { reference: "mrdamascy-tok-hook-1", state: "AUTHORIZED" } ].to_json

    assert_response :ok
    @order.reload
    assert_equal "captured", @order.payment_state
    assert_equal "confirmed", @order.state
    capture = vipps_call_for("/epayment/v1/payments/mrdamascy-tok-hook-1/capture")
    assert_equal "mrdamascy-tok-hook-1-capture", capture[:headers]["Idempotency-Key"]
  end

  test "replayed events are idempotent" do
    ENV["VIPPS_WEBHOOK_SECRET"] = "sekret"
    vipps_real_mode!
    event = [ { reference: "mrdamascy-tok-hook-1", state: "AUTHORIZED" } ].to_json

    2.times do
      post vipps_callback_path,
           headers: { "Content-Type" => "application/json", "Authorization" => "sekret" },
           body: event
      assert_response :ok
    end

    @order.reload
    assert_equal "captured", @order.payment_state
    assert_equal "confirmed", @order.state
  end

  test "ABORTED event marks the payment failed without confirming" do
    ENV["VIPPS_WEBHOOK_SECRET"] = "sekret"
    vipps_real_mode!(remote_state: "ABORTED")

    post vipps_callback_path,
         headers: { "Content-Type" => "application/json", "Authorization" => "sekret" },
         body: [ { reference: "mrdamascy-tok-hook-1", state: "ABORTED" } ].to_json

    assert_response :ok
    @order.reload
    assert_equal "failed", @order.payment_state
    assert_equal "placed", @order.state, "an unpaid order must not start cooking"
  end

  test "unknown references answer 200 without touching anything" do
    ENV["VIPPS_WEBHOOK_SECRET"] = "sekret"
    vipps_real_mode!

    post vipps_callback_path,
         headers: { "Content-Type" => "application/json", "Authorization" => "sekret" },
         body: [ { reference: "mrdamascy-who-dis", state: "AUTHORIZED" } ].to_json

    assert_response :ok
    assert_equal "authorised", @order.reload.payment_state
  end

  test "malformed JSON answers 400" do
    ENV["VIPPS_WEBHOOK_SECRET"] = "sekret"

    post vipps_callback_path,
         headers: { "Content-Type" => "application/json", "Authorization" => "sekret" },
         body: "{not json"

    assert_response :bad_request
  end

  test "single Hash event body is accepted too" do
    ENV["VIPPS_WEBHOOK_SECRET"] = "sekret"
    vipps_real_mode!

    post vipps_callback_path,
         headers: { "Content-Type" => "application/json", "Authorization" => "sekret" },
         body: { reference: "mrdamascy-tok-hook-1", state: "AUTHORIZED" }.to_json

    assert_response :ok
    assert_equal "captured", @order.reload.payment_state
  end
end
