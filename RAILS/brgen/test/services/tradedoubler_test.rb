# frozen_string_literal: true

require "test_helper"
require "minitest/mock"

class TradedoublerTest < ActiveSupport::TestCase
  # Live response shape is still unverified without a publisher token. parse
  # accepts nested XML-ish, flat JSON, and official offers[] documents.

  # These tests count `Shared::AffiliateProduct.where(source: "tradedoubler")` across the
  # whole table, so they assert on a clean database rather than on what they
  # created. That holds on a laptop and fails on the VPS, whose CI seeds ten
  # placeholder tradedoubler rows before the suite runs
  # ("Affiliate: 10 placeholder product(s)") — which is why the same commit gave
  # 303 runs / 0 failures here and "Expected: 2, Actual: 12" there. 12 is the
  # ten seeded rows plus the two the test imported.
  #
  # Clearing the source's rows makes each test measure its own import instead of
  # the database it happened to run against. Scoped to source: "tradedoubler" so
  # nothing else's fixtures are touched.
  setup do
    Shared::AffiliateProduct.where(source: "tradedoubler").delete_all
  end

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

    rows = Shared::Tradedoubler.parse(body)
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

    rows = Shared::Tradedoubler.parse(body)
    assert_equal 1, rows.size
    assert_equal "xyz789", rows.first[:external_id]
    assert_equal "Salomon Speedcross 6", rows.first[:title]
    assert_equal 169_900, rows.first[:price_cents]
  end

  test "parses official offers nested shape" do
    body = {
      "productHeader" => { "totalHits" => 1 },
      "products" => [
        {
          "name" => "Dell Monitor",
          "productImage" => { "url" => "https://img.test/m.jpg" },
          "description" => "27 inch",
          "categories" => [ { "name" => "Electronics" } ],
          "offers" => [
            {
              "feedId" => 8976,
              "productUrl" => "https://pdt.tradedoubler.com/click?a(1)",
              "sourceProductId" => "SKU-1",
              "id" => "519de2b6",
              "programName" => "Dell",
              "availability" => "In Stock",
              "priceHistory" => [
                { "price" => { "value" => "617.28", "currency" => "EUR" }, "date" => 1 }
              ]
            }
          ]
        }
      ]
    }

    rows = Shared::Tradedoubler.parse(body)
    assert_equal 1, rows.size
    row = rows.first
    assert_equal "519de2b6", row[:external_id]
    assert_equal "Dell Monitor", row[:title]
    assert_equal "Dell", row[:merchant]
    assert_equal 61_728, row[:price_cents]
    assert_equal "EUR", row[:currency]
    assert_equal "https://pdt.tradedoubler.com/click?a(1)", row[:click_url]
    assert_equal "Electronics", row[:category]
    assert row[:in_stock]
  end

  test "collapses a single-object response into one row" do
    body = { "products" => { "productId" => "solo", "name" => "One", "clickUrl" => "https://x.test/c" } }
    assert_equal [ "solo" ], Shared::Tradedoubler.parse(body).map { |r| r[:external_id] }
  end

  test "parse tolerates junk without raising" do
    assert_equal [], Shared::Tradedoubler.parse({})
    assert_equal [], Shared::Tradedoubler.parse({ "products" => nil })
    assert_equal [], Shared::Tradedoubler.parse({ "products" => [ "not a hash" ] })
    assert_equal [], Shared::Tradedoubler.parse("a string")
  end

  test "to_cents strips currency noise and thousands separators" do
    assert_equal 24_990, Shared::Tradedoubler.to_cents("249.90")
    assert_equal 24_990, Shared::Tradedoubler.to_cents("249,90")
    assert_equal 24_990, Shared::Tradedoubler.to_cents("NOK 249.90")
    assert_nil Shared::Tradedoubler.to_cents(nil)
    assert_nil Shared::Tradedoubler.to_cents("")
  end

  test "missing availability is treated as in stock" do
    row = Shared::Tradedoubler.parse({ "products" => [ { "id" => "a", "name" => "n", "clickUrl" => "u" } ] }).first
    assert row[:in_stock]

    out = Shared::Tradedoubler.parse({ "products" => [ { "id" => "b", "name" => "n", "clickUrl" => "u", "inStock" => "false" } ] }).first
    refute out[:in_stock]
  end

  test "matrix_uri builds feed-scoped Products URL" do
    uri = Shared::Tradedoubler.matrix_uri("products", matrix: { fid: 42, page: 1, pageSize: 100 }, token: "abc")
    assert_includes uri.to_s, "/1.0/products.json;fid=42;page=1;pageSize=100"
    assert_includes uri.query, "token=abc"
  end

  test "epi helpers compose and append" do
    epi = Shared::Tradedoubler.epi_for(city: "bergen", surface: "newsletter_weekly", edition: "2026-08-01")
    assert_equal "city:bergen|surface:newsletter_weekly|edition:2026-08-01", epi
    url = Shared::Tradedoubler.append_epi("https://clk.test/x?a=1", epi: epi)
    assert_includes url, "epi=city"
  end

  class FakeResponse < Net::HTTPOK
    def initialize(body, code: "200")
      super(nil, code, "OK")
      @body = body
    end
    attr_reader :body
  end

  def product_row(id)
    {
      "id" => id, "productName" => "Produkt #{id}", "clickUrl" => "https://clk.test/#{id}",
      "price" => "199.00", "currency" => "NOK", "merchantName" => "Elkjøp"
    }
  end

  def stub_http(responder)
    Net::HTTP.stub(:get_response, responder) { yield }
  end

  test "import! upserts feed rows and is idempotent across runs" do
    ENV["TRADEDOUBLER_TOKEN"] = "tok_test"
    ENV["TRADEDOUBLER_FEED_IDS"] = "99"
    responder = lambda do |uri|
      assert_includes uri.to_s, "fid=99"
      FakeResponse.new(JSON.generate("products" => [ product_row("a"), product_row("b") ]))
    end
    stub_http(responder) { assert_equal 2, Shared::Tradedoubler.import! }

    assert_equal 2, Shared::AffiliateProduct.where(source: "tradedoubler").count
    row = Shared::AffiliateProduct.find_by!(source: "tradedoubler", external_id: "a")
    assert_equal "Produkt a", row.title
    assert_equal 19_900, row.price_cents
    assert_equal "NOK", row.currency
    assert_equal "NO", row.market
    refute row.placeholder
    assert_not_nil row.last_seen_at

    stub_http(responder) { Shared::Tradedoubler.import! }
    assert_equal 2, Shared::AffiliateProduct.where(source: "tradedoubler").count
  ensure
    ENV.delete("TRADEDOUBLER_TOKEN")
    ENV.delete("TRADEDOUBLER_FEED_IDS")
  end

  test "import! paginates until a short page ends the walk" do
    ENV["TRADEDOUBLER_TOKEN"] = "tok_test"
    ENV["TRADEDOUBLER_FEED_IDS"] = "1"
    full = Array.new(Shared::Tradedoubler::PAGE_SIZE) { |i| product_row("p#{i}") }
    requested = []
    responder = lambda do |uri|
      requested << uri.to_s
      page = uri.path[/page=(\d+)/, 1].to_i
      page = 1 if page.zero?
      body = page == 1 ? full : [ product_row("tail") ]
      FakeResponse.new(JSON.generate("products" => body))
    end
    stub_http(responder) do
      assert_equal Shared::Tradedoubler::PAGE_SIZE + 1, Shared::Tradedoubler.import!
      assert_equal 2, requested.size
    end
  ensure
    ENV.delete("TRADEDOUBLER_TOKEN")
    ENV.delete("TRADEDOUBLER_FEED_IDS")
  end

  test "import! skips rows with no id, click url or title" do
    ENV["TRADEDOUBLER_TOKEN"] = "tok_test"
    ENV["TRADEDOUBLER_FEED_IDS"] = "1"
    responder = lambda do |_uri|
      FakeResponse.new(JSON.generate("products" => [
        { "productName" => "No id", "clickUrl" => "https://clk.test/x" },
        { "id" => "no-url", "productName" => "No click url" },
        { "id" => "no-title", "clickUrl" => "https://clk.test/y" },
        product_row("good")
      ]))
    end
    stub_http(responder) { assert_equal 1, Shared::Tradedoubler.import! }
    assert_equal [ "good" ], Shared::AffiliateProduct.where(source: "tradedoubler").pluck(:external_id)
  ensure
    ENV.delete("TRADEDOUBLER_TOKEN")
    ENV.delete("TRADEDOUBLER_FEED_IDS")
  end

  test "import! is a no-op with no token and makes no request" do
    ENV.delete("TRADEDOUBLER_TOKEN")
    ENV.delete("TRADEDOUBLER_PRODUCTS_TOKEN")
    called = false
    stub_http(->(_uri) { called = true; FakeResponse.new("{}") }) do
      assert_equal 0, Shared::Tradedoubler.import!
    end
    refute called
  end

  test "import! is a no-op without feed ids when discovery is empty" do
    ENV["TRADEDOUBLER_TOKEN"] = "tok_test"
    ENV.delete("TRADEDOUBLER_FEED_IDS")
    responder = lambda do |uri|
      if uri.path.include?("productFeeds")
        FakeResponse.new(JSON.generate("feeds" => []))
      else
        flunk "should not search without feeds: #{uri}"
      end
    end
    stub_http(responder) { assert_equal 0, Shared::Tradedoubler.import! }
  ensure
    ENV.delete("TRADEDOUBLER_TOKEN")
  end

  test "a non-success response yields no rows and does not raise" do
    ENV["TRADEDOUBLER_TOKEN"] = "tok_test"
    ENV["TRADEDOUBLER_FEED_IDS"] = "1"
    failure = Net::HTTPForbidden.new(nil, "403", "Forbidden")
    Net::HTTP.stub(:get_response, ->(_uri) { failure }) do
      assert_equal 0, Shared::Tradedoubler.import!
    end
    assert_equal 0, Shared::AffiliateProduct.where(source: "tradedoubler").count
  ensure
    ENV.delete("TRADEDOUBLER_TOKEN")
    ENV.delete("TRADEDOUBLER_FEED_IDS")
  end

  test "not configured without a token, and deals falls back to stored rows" do
    ENV.delete("TRADEDOUBLER_TOKEN")
    ENV.delete("TRADEDOUBLER_PRODUCTS_TOKEN")
    refute Shared::Tradedoubler.configured?

    Shared::AffiliateProduct.upsert_from_feed!(
      source: "tradedoubler", external_id: "stored-1", title: "Stored product",
      click_url: "https://example.test/p", market: "NO", category: "electronics",
      price_cents: 10_000, currency: "NOK", merchant: "Elkjøp", in_stock: true, placeholder: true
    )

    deals = Shared::Tradedoubler.deals(category: "electronics", limit: 5)
    assert_equal 1, deals.size
    assert_equal "Stored product", deals.first.title
    assert deals.first.placeholder
  end
end
