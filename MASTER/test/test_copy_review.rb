# frozen_string_literal: true

require_relative "test_helper"
require_relative "../lib/review/copy_review"

class TestCopyReview < Minitest::Test
  Review = Master::Review::CopyReview

  def setup
    @now = Time.utc(2026, 10, 31, 12)
    @product = {
      source: "tradedoubler", external_id: "td-42", title: "Kjole",
      merchant: "Fjord Studio", program_id: "programme-7",
      price_cents: 14_990, currency: "NOK", category: "Klær", market: "NO",
      in_stock: true, placeholder: false, last_seen_at: @now - 60
    }
    @creative = {
      headline: "Kjole – NOK 149.90",
      body: "Kjole fra Fjord Studio. På lager.",
      cta: "Se produktet", locale: "nb-NO",
      disclosure: "Annonse – annonselenke",
      claims: [
        { kind: "product_title", text: "Kjole" },
        { kind: "merchant", text: "Fjord Studio" },
        { kind: "price", text: "NOK 149.90" },
        { kind: "availability", text: "På lager" }
      ]
    }
  end

  def review(creative: @creative, product: @product, **options)
    Review.review(creative:, product:, now: @now, **options)
  end

  def test_supported_feed_claims_and_disclosure_pass
    report = review
    assert report.pass?, report.findings.select { |item| item.status != :pass }.inspect
    assert_equal({ pass: report.findings.size, fail: 0, inconclusive: 0 }, report.summary)
    assert_equal true, report.evidence.fetch(:read_only)
    assert_equal "td-42", report.evidence.dig(:product, :external_id)
  end

  def test_price_claim_must_match_integer_minor_units_and_currency
    creative = @creative.merge(headline: "Kjole – NOK 99.00", claims: @creative[:claims].map(&:dup))
    creative[:claims][2][:text] = "NOK 99.00"
    report = review(creative:)
    assert report.fail?
    assert_includes report.findings.map(&:code), :price_claim_mismatch
    assert_includes report.findings.map(&:code), :price_amount_mismatch
  end

  def test_stale_inventory_cannot_pass
    report = review(product: @product.merge(last_seen_at: @now - 8 * 24 * 60 * 60))
    assert report.fail?
    assert_includes report.findings.map(&:code), :inventory_stale
  end

  def test_placeholder_inventory_cannot_pass
    report = review(product: @product.merge(placeholder: true))
    assert report.fail?
    assert_includes report.findings.map(&:code), :placeholder_inventory
  end

  def test_out_of_stock_inventory_cannot_pass
    report = review(product: @product.merge(in_stock: false))
    assert report.fail?
    assert_includes report.findings.map(&:code), :product_out_of_stock
    assert_includes report.findings.map(&:code), :availability_claim_mismatch
  end

  def test_missing_claim_ledger_is_inconclusive_not_pass
    report = review(creative: @creative.reject { |key, _value| key == :claims })
    assert report.inconclusive?
    assert_includes report.findings.map(&:code), :claim_ledger_missing
  end

  def test_external_claim_remains_inconclusive
    creative = @creative.merge(
      headline: "Ranked first in Norway",
      claims: [{ kind: "ranking", text: "Ranked first in Norway", reference: "publisher ranking 2026" }]
    )
    report = review(creative:)
    assert report.inconclusive?
    finding = report.findings.find { |item| item.code == :external_claim_unverified }
    refute_nil finding
    assert_equal "publisher ranking 2026", finding.evidence.fetch(:reference)
  end

  def test_missing_affiliate_disclosure_fails
    report = review(creative: @creative.merge(disclosure: ""))
    assert report.fail?
    assert_includes report.findings.map(&:code), :affiliate_disclosure_missing
  end

  def test_wrong_market_fails
    report = review(market: "SE")
    assert report.fail?
    assert_includes report.findings.map(&:code), :market_mismatch
  end

  def test_mismatched_currency_fails
    creative = @creative.merge(headline: "Kjole – USD 149.90", claims: @creative[:claims].map(&:dup))
    creative[:claims][2][:text] = "USD 149.90"
    report = review(creative:)
    assert report.fail?
    assert_includes report.findings.map(&:code), :price_claim_mismatch
  end

  def test_missing_product_snapshot_is_inconclusive
    report = review(product: nil)
    assert report.inconclusive?
    assert_includes report.findings.map(&:code), :product_snapshot_missing
  end

  def test_review_does_not_mutate_inputs
    creative_before = @creative.merge(claims: @creative[:claims].map(&:dup))
    product_before = @product.dup
    review
    assert_equal creative_before, @creative
    assert_equal product_before, @product
  end
end
