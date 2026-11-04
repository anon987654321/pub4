# frozen_string_literal: true

require "test_helper"

# Poll sync (APP_SPEC §5/§8): the customer lands on /track straight from the
# Vipps app, so the tracking page itself — load and the 10 s status poll —
# reconciles the payment. No refresh, no extra tap: Vipps says AUTHORIZED →
# we capture → the timeline flips to confirmed.
class VippsPollSyncTest < ActionDispatch::IntegrationTest
  setup do
    @kitchen = seed_kitchen!
    @order = seed_order!(token: "tok-poll-1")
    @order.update!(payment_state: "authorised", vipps_order_id: "mrdamascy-tok-poll-1")
    vipps_reset_token_cache!
  end

  teardown do
    vipps_restore_http!
  end

  test "mock mode: status reports payment_state and sync is a no-op" do
    get track_status_path(token: "tok-poll-1"), as: :json

    assert_response :ok
    body = JSON.parse(response.body)
    assert_equal "placed", body["state"]
    assert_equal "authorised", body["payment_state"]
    assert_equal "authorised", @order.reload.payment_state
  end

  test "real mode: tracking page load captures an AUTHORIZED payment" do
    vipps_real_mode!

    get track_path(token: "tok-poll-1")

    assert_response :ok
    @order.reload
    assert_equal "captured", @order.payment_state
    assert_equal "confirmed", @order.state
    assert_match(/Sahtein|صحتين/, response.body, "the paid landing must say Sahtein")
  end

  test "real mode: the 10 s status poll completes a payment the webhook missed" do
    vipps_real_mode!

    get track_status_path(token: "tok-poll-1"), as: :json

    assert_response :ok
    body = JSON.parse(response.body)
    assert_equal "confirmed", body["state"]
    assert_equal "captured", body["payment_state"]
  end

  test "real mode: ABORTED payment shows as failed, order stays placed" do
    vipps_real_mode!(remote_state: "ABORTED")

    get track_status_path(token: "tok-poll-1"), as: :json

    body = JSON.parse(response.body)
    assert_equal "placed", body["state"]
    assert_equal "failed", body["payment_state"]
  end

  test "failed payments are not asked about again" do
    @order.update!(payment_state: "failed")
    vipps_real_mode!

    get track_status_path(token: "tok-poll-1"), as: :json

    assert_equal "failed", JSON.parse(response.body)["payment_state"]
    assert_equal 0, vipps_calls.count, "no Vipps HTTP once the payment has failed"
  end

  test "captured orders are left alone by later polls" do
    @order.update!(payment_state: "captured", state: "confirmed")
    vipps_real_mode!

    get track_status_path(token: "tok-poll-1"), as: :json

    body = JSON.parse(response.body)
    assert_equal "captured", body["payment_state"]
    assert_equal 0, vipps_calls.count, "no Vipps HTTP for an already-captured order"
  end
end
