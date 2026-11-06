# frozen_string_literal: true

require "test_helper"
class CopyReviewCheckTest < ActiveSupport::TestCase
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

  test "a current supplied product snapshot can pass deterministic copy checks" do
    prepared = CopyReviewCheck.prepare(creative: creative, product: product, market: "NO")
    result = CopyReviewCheck.call(prepared)

    assert_equal :pass, result.report.status
    assert_equal 64, result.creative_sha256.length
    assert_equal 64, result.product_sha256.length
    assert_equal 64, result.reviewer_sha256.length
    assert_equal true, result.report.evidence[:read_only]
  end

  test "a missing product snapshot remains inconclusive rather than passing" do
    prepared = CopyReviewCheck.prepare(creative: creative)
    result = CopyReviewCheck.call(prepared)

    assert_equal :inconclusive, result.report.status
    assert_nil result.product_sha256
    assert_includes result.report.findings.map(&:code), :product_snapshot_missing
  end

  test "unsupported fields are rejected instead of silently trusted" do
    assert_raises(CopyReviewCheck::InvalidInput) do
      CopyReviewCheck.prepare(creative: creative.merge(visitor_token: "visitor"))
    end
  end

  test "each claim must be an object using only declared fields" do
    invalid = creative.merge(claims: ["a free-form claim"])
    assert_raises(CopyReviewCheck::InvalidInput) do
      CopyReviewCheck.prepare(creative: invalid, product: product)
    end

    invalid = creative.merge(claims: [{ kind: "price", text: "149.90", confidence: 1.0 }])
    assert_raises(CopyReviewCheck::InvalidInput) do
      CopyReviewCheck.prepare(creative: invalid, product: product)
    end
  end

  test "field values must have the declared primitive types" do
    assert_raises(CopyReviewCheck::InvalidInput) do
      CopyReviewCheck.prepare(creative: creative.merge(headline: { text: "Wool coat" }))
    end

    assert_raises(CopyReviewCheck::InvalidInput) do
      CopyReviewCheck.prepare(creative: creative, product: product.merge(in_stock: "yes"))
    end

    assert_raises(CopyReviewCheck::InvalidInput) do
      CopyReviewCheck.prepare(creative: creative, product: product, market: ["NO"])
    end
  end

  test "oversized input is refused" do
    invalid = creative.merge(body: "x" * (CopyReviewCheck::MAX_INPUT_BYTES + 1))
    assert_raises(CopyReviewCheck::InvalidInput) do
      CopyReviewCheck.prepare(creative: invalid, product: product)
    end
  end
end
