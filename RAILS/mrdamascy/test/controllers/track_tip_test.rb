# frozen_string_literal: true

require "test_helper"

# Tracking is public by token — no login required. The tip and review forms
# appear after delivery. Tips sit behind config.x.tips (off by default, since
# neither payment lane can charge one), so these tests turn it on.
class TrackTipTest < ActionDispatch::IntegrationTest
  setup do
    @order = seed_order!(state: "delivered", delivery_mode: "delivery")
    @tips_were = Rails.configuration.x.tips
    Rails.configuration.x.tips = true
  end

  teardown do
    Rails.configuration.x.tips = @tips_were
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

  test "a tip is recorded beside the total, which stays what was paid" do
    post order_tip_url(@order.tracking_token), params: { tip_ore: 2000 }

    assert_redirected_to track_path(@order.tracking_token)
    assert_equal I18n.t("flash.tip_thanks"), flash[:notice]
    assert_equal 2000, @order.reload.tip_ore
    assert_equal 15_800, @order.total_ore
  end

  test "choosing no tip records none and thanks for the order, not for a tip" do
    post order_tip_url(@order.tracking_token), params: { tip_ore: 0 }

    assert_equal I18n.t("orders.thanks"), flash[:notice]
    assert_equal 0, @order.reload.tip_ore
  end

  test "an order takes one tip, and the chosen chip shows pressed" do
    post order_tip_url(@order.tracking_token), params: { tip_ore: 2000 }
    post order_tip_url(@order.tracking_token), params: { tip_ore: 4000 }

    assert_redirected_to track_path(@order.tracking_token)
    assert_equal I18n.t("orders.tip_refused"), flash[:alert]
    assert_equal 2000, @order.reload.tip_ore

    get track_url(@order.tracking_token)
    assert_select "button[aria-pressed=true][disabled]", text: I18n.t("orders.tip_20")
    assert_select "button[aria-pressed=false][disabled]", count: 2
  end

  test "an order not yet delivered takes no tip" do
    on_the_way = seed_order!(state: "picked_up", delivery_mode: "delivery")

    post order_tip_url(on_the_way.tracking_token), params: { tip_ore: 4000 }

    assert_equal I18n.t("orders.tip_refused"), flash[:alert]
    assert_equal 0, on_the_way.reload.tip_ore
  end

  test "with tips off the chips are gone and the endpoint takes nothing" do
    Rails.configuration.x.tips = false

    get track_url(@order.tracking_token)
    assert_select ".tip-choices", count: 0

    post order_tip_url(@order.tracking_token), params: { tip_ore: 2000 }
    assert_response :not_found
    assert_equal 0, @order.reload.tip_ore
  end

  test "the zero chip leaves the total untouched — no pressure" do
    # The chips are 0/20/40 kr; the 0 chip must be a safe no-op (the controller
    # skips Order#add_tip! for 0 — the model refuses non-positive amounts).
    post order_tip_url(@order.tracking_token), params: { tip_ore: 0 }

    assert_includes [ 200, 302, 303 ], response.status
    assert_equal 0, @order.reload.tip_ore
    assert_equal 15800, @order.total_ore
  end

  test "a review can be left from the track page" do
    sign_in(@order.user)

    assert_difference "Review.count", 1 do
      post order_review_url(@order), params: { review: { rating: 5, body: "Beste toumen i Bergen" } }
    end

    assert_includes [ 200, 302, 303 ], response.status
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
