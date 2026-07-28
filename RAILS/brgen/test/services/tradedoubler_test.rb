# frozen_string_literal: true

require "test_helper"
# Object#stub, used below to fake the HTTP transport.
require "minitest/mock"

class TradedoublerTest < ActiveSupport::TestCase
  # The live response shape could not be verified (brgen.no is not an approved
  # publisher yet, so there is no token to call with). parse therefore accepts
  # both plausible shapes, and these tests pin that tolerance down — the
  # previous implementation only handled the nested XML-ish shape and would have
  # silently returned zero products if the API answers with flat JSON.
  test "parses the nested products.product shape" do
    body = {
      "products" => {
        "product" => [
          {
            "productId" => "abc123",
            "name" => "Bergans regnjakke",
            "description" => "Skalljakke",
            "imageUrl" => "https://example.test/j.jpg",
            "productUrl" => "https://clk.tradedoubler.test/click?p=1",
            "program" => { "name" => "XXL", "id" => "999" },
            "fields" => { "Price" => "1499.00", "Currency" => "NOK" }
          }
        ]
      }
    }

    rows = Tradedoubler.parse(body)
    assert_equal 1, rows.size
    row = rows.first
    assert_equal "abc123", row[:external_id]
    assert_equal "Bergans regnjakke", row[:title]
    assert_equal "XXL", row[:merchant]
    assert_equal "999", row[:program_id]
    assert_equal 149_900, row[:price_cents]
    assert_equal "NOK", row[:currency]
    assert_equal "https://clk.tradedoubler.test/click?p=1", row[:click_url]
  end

  test "parses the flat products array shape" do
    body = {
      "products" => [
        {
          "id" => "xyz789",
          "productName" => "Salomon Speedcross 6",
          "clickUrl" => "https://clk.tradedoubler.test/click?p=2",
          "price" => "1699,00",
          "currency" => "NOK",
          "merchantName" => "XXL"
        }
      ]
    }

    rows = Tradedoubler.parse(body)
    assert_equal 1, rows.size
    assert_equal "xyz789", rows.first[:external_id]
    assert_equal "Salomon Speedcross 6", rows.first[:title]
    # Comma decimal separator, as Norwegian feeds report it.
    assert_equal 169_900, rows.first[:price_cents]
  end

  test "collapses a single-object response into one row" do
    body = { "products" => { "productId" => "solo", "name" => "One", "clickUrl" => "https://x.test/c" } }
    assert_equal [ "solo" ], Tradedoubler.parse(body).map { |r| r[:external_id] }
  end

  test "parse tolerates junk without raising" do
    assert_equal [], Tradedoubler.parse({})
    assert_equal [], Tradedoubler.parse({ "products" => nil })
    assert_equal [], Tradedoubler.parse({ "products" => [ "not a hash" ] })
    assert_equal [], Tradedoubler.parse("a string")
  end

  test "to_cents strips currency noise and thousands separators" do
    assert_equal 24_990, Tradedoubler.to_cents("249.90")
    assert_equal 24_990, Tradedoubler.to_cents("249,90")
    assert_equal 24_990, Tradedoubler.to_cents("NOK 249.90")
    assert_nil Tradedoubler.to_cents(nil)
    assert_nil Tradedoubler.to_cents("")
  end

  # in_stock absent must not be read as out of stock — that would hide every
  # product from a feed that simply doesn't report availability.
  test "missing availability is treated as in stock" do
    row = Tradedoubler.parse({ "products" => [ { "id" => "a", "name" => "n", "clickUrl" => "u" } ] }).first
    assert row[:in_stock]

    out = Tradedoubler.parse({ "products" => [ { "id" => "b", "name" => "n", "clickUrl" => "u", "inStock" => "false" } ] }).first
    refute out[:in_stock]
  end

  # The parser tests above cover shape. These cover the pipeline the first real
  # call will actually run: HTTP -> parse -> upsert. Without a token there is no
  # way to exercise it for real, so the transport is stubbed — but everything
  # downstream of the response body is the production path.
  class FakeResponse < Net::HTTPOK
    def initialize(body)
      super(nil, "200", "OK")
      @body = body
    end
    attr_reader :body
  end

  def stub_pages(pages)
    requested = []
    responder = lambda do |uri|
      requested << uri
      page = URI.decode_www_form(uri.query).to_h["page"].to_i
      FakeResponse.new(JSON.generate("products" => pages[page] || []))
    end
    Net::HTTP.stub(:get_response, responder) do
      yield requested
    end
  end

  def product_row(id)
    {
      "id" => id, "productName" => "Produkt #{id}", "clickUrl" => "https://clk.test/#{id}",
      "price" => "199.00", "currency" => "NOK", "merchantName" => "Elkjøp"
    }
  end

  test "import! upserts feed rows and is idempotent across runs" do
    ENV["TRADEDOUBLER_TOKEN"] = "tok_test"
    stub_pages(1 => [ product_row("a"), product_row("b") ]) do
      assert_equal 2, Tradedoubler.import!
    end

    assert_equal 2, AffiliateProduct.where(source: "tradedoubler").count
    row = AffiliateProduct.find_by!(source: "tradedoubler", external_id: "a")
    assert_equal "Produkt a", row.title
    assert_equal 19_900, row.price_cents
    assert_equal "NOK", row.currency
    assert_equal "NO", row.market
    refute row.placeholder, "imported rows are real inventory, not placeholders"
    assert_not_nil row.last_seen_at

    # A second run must refresh, not duplicate.
    stub_pages(1 => [ product_row("a"), product_row("b") ]) do
      Tradedoubler.import!
    end
    assert_equal 2, AffiliateProduct.where(source: "tradedoubler").count
  ensure
    ENV.delete("TRADEDOUBLER_TOKEN")
  end

  test "import! paginates until a short page ends the walk" do
    ENV["TRADEDOUBLER_TOKEN"] = "tok_test"
    full = Array.new(Tradedoubler::PAGE_SIZE) { |i| product_row("p#{i}") }
    stub_pages(1 => full, 2 => [ product_row("tail") ]) do |requested|
      assert_equal Tradedoubler::PAGE_SIZE + 1, Tradedoubler.import!
      assert_equal 2, requested.size, "a short second page should stop the walk"
    end
  ensure
    ENV.delete("TRADEDOUBLER_TOKEN")
  end

  # No stable network id means no upsert key, so a re-import would duplicate the
  # row on every run. Same for a missing click_url: an affiliate row you cannot
  # click is worthless and would render a dead link.
  test "import! skips rows with no id, click url or title" do
    ENV["TRADEDOUBLER_TOKEN"] = "tok_test"
    stub_pages(1 => [
      { "productName" => "No id", "clickUrl" => "https://clk.test/x" },
      { "id" => "no-url", "productName" => "No click url" },
      { "id" => "no-title", "clickUrl" => "https://clk.test/y" },
      product_row("good")
    ]) do
      assert_equal 1, Tradedoubler.import!
    end
    assert_equal [ "good" ], AffiliateProduct.where(source: "tradedoubler").pluck(:external_id)
  ensure
    ENV.delete("TRADEDOUBLER_TOKEN")
  end

  test "import! is a no-op with no token and makes no request" do
    ENV.delete("TRADEDOUBLER_TOKEN")
    called = false
    Net::HTTP.stub(:get_response, ->(_uri) { called = true; FakeResponse.new("{}") }) do
      assert_equal 0, Tradedoubler.import!
    end
    refute called, "must not call out without a configured token"
  end

  test "a non-success response yields no rows and does not raise" do
    ENV["TRADEDOUBLER_TOKEN"] = "tok_test"
    failure = Net::HTTPForbidden.new(nil, "403", "Forbidden")
    Net::HTTP.stub(:get_response, ->(_uri) { failure }) do
      assert_equal 0, Tradedoubler.import!
    end
    assert_equal 0, AffiliateProduct.where(source: "tradedoubler").count
  ensure
    ENV.delete("TRADEDOUBLER_TOKEN")
  end

  test "not configured without a token, and deals falls back to stored rows" do
    ENV.delete("TRADEDOUBLER_TOKEN")
    refute Tradedoubler.configured?

    AffiliateProduct.upsert_from_feed!(
      source: "tradedoubler", external_id: "stored-1", title: "Stored product",
      click_url: "https://example.test/p", market: "NO", category: "electronics",
      price_cents: 10_000, currency: "NOK", merchant: "Elkjøp", in_stock: true, placeholder: true
    )

    deals = Tradedoubler.deals(category: "electronics", limit: 5)
    assert_equal 1, deals.size
    assert_equal "Stored product", deals.first.title
    assert deals.first.placeholder, "a placeholder row must stay flagged through to the view"
  end
end
