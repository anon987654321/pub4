# frozen_string_literal: true

require "test_helper"

# Tracking is public by token — no login required. The tip and review forms
# appear after delivery; the tip updates the order total in øre.
class TrackTipTest < ActionDispatch::IntegrationTest
  setup do
    @order = seed_order!(state: "delivered", delivery_mode: "delivery")
  end

  test "the track page is public by token and says Sahtein when delivered" do
    get track_url(@order.tracking_token)
    assert_response :success

    assert_match(/Sahtein|صحتين/, response.body)  # orders.thanks
    assert_match "Levert", response.body          # orders.states.delivered
    assert_match "20 kr", response.body           # tip chip
  end

  test "the status endpoint returns json with state and eta" do
    get track_status_url(@order.tracking_token)
    assert_response :success

    data = JSON.parse(response.body)
    assert_equal "delivered", data["state"]
    assert data.key?("eta")
  end

  test "a tip updates the tip and the total" do
    post order_tip_url(@order.tracking_token), params: { tip_ore: 2000 }

    assert_redirected_to track_path(@order.tracking_token)
    assert_equal 2000, @order.reload.tip_ore
    assert_equal 15800 + 2000, @order.total_ore
  end

  test "the zero chip leaves the total untouched — no pressure" do
    # The chips are 0/20/40 kr; the 0 chip must be a safe no-op (the controller
    # skips Order#add_tip! for 0 — the model refuses non-positive amounts).
    post order_tip_url(@order.tracking_token), params: { tip_ore: 0 }

    assert_includes [200, 302, 303], response.status
    assert_equal 0, @order.reload.tip_ore
    assert_equal 15800, @order.total_ore
  end

  test "a review can be left from the track page" do
    sign_in(@order.user)

    assert_difference "Review.count", 1 do
      post order_review_url(@order), params: { review: { rating: 5, body: "Beste toumen i Bergen" } }
    end

    assert_includes [200, 302, 303], response.status
    review = Review.last
    assert_equal 5, review.rating
    assert_equal @order.id, review.order_id
    assert_equal @order.user_id, review.user_id
  end

  # Order ids are sequential; the review endpoint looked them up for anyone and
  # redirected to the order's tracking page, token and all.
  test "another customer's order can be neither reviewed nor traced through the review endpoint" do
    sign_in(seed_customer!(name: "Nabo"))

    assert_no_difference "Review.count" do
      post order_review_url(@order), params: { review: { rating: 1, body: "ikke min" } }
    end
    assert_response :not_found
    refute_includes response.headers["Location"].to_s, @order.tracking_token
  end

  test "a signed-out visitor is sent to sign in without the order's tracking token" do
    post order_review_url(@order), params: { review: { rating: 5 } }

    assert_redirected_to new_session_path
    refute_includes response.headers["Location"].to_s, @order.tracking_token
  end
end
