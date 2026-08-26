# frozen_string_literal: true

require "test_helper"

# TradeDoubler answers in more than one shape, and every method in
# tradedoubler_parsing.rb exists because a feed came back in one the previous
# version did not handle. None of it was pinned: the file had no test, so the
# only thing between a feed changing shape and the sidebar silently going empty
# was somebody noticing.
#
# Written when the parsing half was split out of tradedoubler.rb. The split was
# proved by diffing its output against the pre-split file over these payloads;
# this keeps that comparison, so the next shape change has something to fail
# against.
#
# It lives in brgen's suite rather than RAILS/test because the parsing depends
# on ActiveSupport (`presence`, `truncate`) — the first draft of this file ran
# under bare ruby on the assumption that it did not, and that assumption is what
# the errors corrected.
class TradedoublerParsingTest < ActiveSupport::TestCase
  def parse(body) = Shared::Tradedoubler.parse(body)

  # The official Products API: price under offers[].priceHistory[].price.
  test "nested offer shape" do
    rows = parse(
      "products" => [ {
        "name" => "Kjole",
        "productImage" => { "url" => "http://x/i.jpg" },
        "offers" => [ {
          "priceHistory" => [ { "price" => { "value" => "199.00", "currency" => "NOK" } } ],
          "productUrl" => "http://x/p",
          "programName" => "Shop",
          "availability" => { "inStock" => true },
        } ],
      } ]
    )

    assert_equal 1, rows.length
    assert_equal "Kjole", rows.first[:title]
    assert_equal 19_900, rows.first[:price_cents], "price arrives in kroner and is stored in øre"
    assert_equal "NOK", rows.first[:currency]
    assert_equal "Shop", rows.first[:merchant]
    assert rows.first[:in_stock]
  end

  # The legacy flat shape: price and currency directly on the product.
  test "flat legacy shape" do
    rows = parse(
      "products" => [ {
        "name" => "Sko", "imageUrl" => "http://x/s.jpg", "price" => "499",
        "currency" => "NOK", "productUrl" => "http://x/s", "programName" => "Butikk",
      } ]
    )

    assert_equal 1, rows.length
    assert_equal 49_900, rows.first[:price_cents]
    assert_equal "http://x/s.jpg", rows.first[:image_url]
  end

  test "one product arrives as a hash rather than a list" do
    assert_equal [ "Jakke" ],
                 parse("product" => { "name" => "Jakke", "productUrl" => "http://x/j" }).map { |r| r[:title] }
  end

  test "and sometimes the body is the list" do
    assert_equal [ "Skjerf" ],
                 parse([ { "name" => "Skjerf", "productUrl" => "http://x/k" } ]).map { |r| r[:title] }
  end

  # A shape nobody anticipated must return nothing, not raise: this runs inside
  # an import job, where an exception stops the whole feed rather than one row.
  test "unknown shapes are empty rather than an exception" do
    [ { "nope" => true }, [], nil, "a string", 42 ].each do |body|
      assert_equal [], parse(body), "#{body.inspect} should parse to no deals"
    end
  end

  # A feed that says nothing about availability is not saying the item is gone,
  # and defaulting the other way empties the sidebar.
  test "availability absent is in stock" do
    assert parse("products" => [ { "name" => "Belte", "productUrl" => "http://x/b" } ]).first[:in_stock]
  end

# A scalar availability is read; a nested one is not, and this pins the
# difference rather than the wish.
#
# `dig` takes alternative KEYS, not a path — dig.call("availability",
# "inStock") means "availability, or failing that inStock", so a feed sending
# availability: { inStock: false } hands in_stock? a Hash. `.to_s.downcase` on
# it matches none of the out-of-stock strings and the fallback then finds no
# top-level inStock either, so the row reads as stocked.
#
# Whether TradeDoubler ever sends that shape is unmeasured — the nested
# payload above is constructed, not captured — so this records the behaviour
# instead of changing it. If a real feed turns up with a nested availability,
# this test is where the evidence goes and in_stock? is what changes.
test "a scalar out-of-stock string is respected" do
  rows = parse(
    "products" => [ { "name" => "Lue", "productUrl" => "http://x/l",
                      "availability" => "out of stock" } ]
  )

  assert_not rows.first[:in_stock]
end

test "a nested availability hash is not read, and reads as in stock" do
  rows = parse(
    "products" => [ { "name" => "Lue", "productUrl" => "http://x/l",
                      "offers" => [ { "availability" => { "inStock" => false } } ] } ]
  )

  assert rows.first[:in_stock],
         "documented limitation: in_stock? compares a Hash against out-of-stock strings"
end

  # Deal is Tradedoubler's constant and the parsing module is extended into
  # Tradedoubler rather than nested inside it, so a bare `Deal` resolves to
  # nothing and raises at the first call rather than at load. This is that call.
  test "row_to_deal reaches the qualified Deal constant" do
    deal = Shared::Tradedoubler.row_to_deal(
      title: "Kjole", description: "d", merchant: "Shop", price_cents: 19_900,
      currency: "NOK", image_url: "http://x/i.jpg", click_url: "http://x/p"
    )

    assert_equal "Kjole", deal.title
    assert_equal "199.00", deal.price, "price_cents renders back to kroner for display"
    assert_not deal.placeholder
  end
end
