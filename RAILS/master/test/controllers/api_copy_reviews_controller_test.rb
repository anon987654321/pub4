# frozen_string_literal: true

require "test_helper"

class ApiCopyReviewsControllerTest < ActionDispatch::IntegrationTest
  setup do
    subscription = {
      "id" => "sub_copy_review_1",
      "status" => "active",
      "customer" => "cus_copy_review_1",
      "metadata" => { "plan" => "master_api_team" }
    }
    @key = ApiKey.sync!(subscription)
    @token = @key.reveal!
  end

  def creative
    {
      headline: "Wool coat — NOK 149.90",
      body: "Wool coat from Fjord Studio. In stock.",
      cta: "View item",
      locale: "en",
      disclosure: "Advertisement",
      claims: [
        { kind: "product_title", text: "Wool coat" },
        { kind: "merchant", text: "Fjord Studio" },
        { kind: "price", text: "NOK 149.90" },
        { kind: "availability", text: "In stock" }
      ]
    }
  end

  def product
    {
      source: "tradedoubler",
      external_id: "td-42",
      title: "Wool coat",
      merchant: "Fjord Studio",
      price_cents: 14_990,
      currency: "NOK",
      market: "NO",
      in_stock: true,
      placeholder: false,
      last_seen_at: Time.current.iso8601
    }
  end

  def copy_review(payload = { creative: creative, product: product, market: "NO" }, token: @token)
    post "/api/v1/copy-review",
         params: payload.to_json,
         headers: {
           "Authorization" => "Bearer #{token}",
           "Content-Type" => "application/json"
         }
  end

  test "a valid request returns a deterministic report and charges one existing API check" do
    copy_review

    assert_response :success
    body = response.parsed_body
    assert_equal "pass", body.dig("review", "status")
    assert_equal "caller_supplied_unverified", body.dig("provenance", "source_trust")
    assert_equal false, body.dig("provenance", "stored_copy")
    assert_equal false, body.dig("provenance", "certification")
    assert_equal 1, body.dig("usage", "used")
    assert_equal 1, ApiCopyReview.where(api_key: @key).count
  end

  test "a receipt stores hashes and finding codes but never supplied copy or product fields" do
    copy_review

    receipt = ApiCopyReview.find_by!(api_key: @key)
    serialized = receipt.attributes.to_json

    refute_includes serialized, "Wool coat"
    refute_includes serialized, "Fjord Studio"
    refute_includes serialized, "149.90"
    assert_match(/\A[0-9a-f]{64}\z/, receipt.creative_sha256)
    assert_match(/\A[0-9a-f]{64}\z/, receipt.product_sha256)
    assert_match(/\A[0-9a-f]{64}\z/, receipt.reviewer_sha256)
  end

  test "without a product snapshot the report says inconclusive" do
    copy_review({ creative: creative, market: "NO" })

    assert_response :success
    assert_equal "inconclusive", response.parsed_body.dig("review", "status")
    assert_nil response.parsed_body.dig("provenance", "product_sha256")
  end

  test "invalid fields are refused before consuming quota or creating a receipt" do
    copy_review({ creative: creative.merge(visitor_token: "not-allowed"), product: product })

    assert_response :unprocessable_entity
    assert_equal 0, @key.reload.usage_count
    assert_equal 0, ApiCopyReview.count
  end

  test "an unknown or missing bearer key cannot reach the reviewer" do
    copy_review({ creative: creative, product: product }, token: "mk_live_invalid")

    assert_response :unauthorized
    assert_equal 0, @key.reload.usage_count
    assert_equal 0, ApiCopyReview.count
  end

  test "an inactive subscription is refused without charging" do
    @key.update!(status: "past_due")
    copy_review

    assert_response :payment_required
    assert_equal 0, @key.reload.usage_count
    assert_equal 0, ApiCopyReview.count
  end

  test "an exhausted monthly quota is refused without a receipt" do
    @key.update!(usage_period: ApiKey.current_period, usage_count: @key.quota)
    copy_review

    assert_response :too_many_requests
    assert_equal "quota_exhausted", response.parsed_body["error"]
    assert_equal @key.quota, @key.reload.usage_count
    assert_equal 0, ApiCopyReview.count
  end

  test "an oversized body is rejected before parameter processing" do
    body = { creative: creative.merge(body: "x" * (CopyReviewCheck::MAX_INPUT_BYTES + 8_000)) }.to_json
    post "/api/v1/copy-review", params: body,
         headers: { "Authorization" => "Bearer #{@token}", "Content-Type" => "application/json" }

    assert_response :payload_too_large
    assert_equal 0, @key.reload.usage_count
    assert_equal 0, ApiCopyReview.count
  end
end
