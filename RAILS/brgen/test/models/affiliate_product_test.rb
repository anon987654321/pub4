# frozen_string_literal: true

require "test_helper"

class AffiliateProductTest < ActiveSupport::TestCase
  def build_product(**overrides)
    Shared::AffiliateProduct.new({
      source: "tradedoubler",
      external_id: "x1",
      title: "Produkt",
      click_url: "https://example.test/p",
      market: "NO",
      last_seen_at: Time.current
    }.merge(overrides))
  end

  test "requires a known source" do
    assert build_product.valid?
    refute build_product(source: "not_a_network").valid?
    refute build_product(source: nil).valid?
  end

  test "external_id is unique per source but reusable across sources" do
    build_product(source: "tradedoubler", external_id: "dup").save!
    refute build_product(source: "tradedoubler", external_id: "dup").valid?
    # An ASIN and a TradeDoubler productId may legitimately collide as strings.
    assert build_product(source: "amazon", external_id: "dup").valid?
  end

  test "upsert_from_feed! updates in place rather than duplicating" do
    first = Shared::AffiliateProduct.upsert_from_feed!(
      source: "tradedoubler", external_id: "up1", title: "Gammel tittel",
      click_url: "https://example.test/a", price_cents: 1_000
    )
    second = Shared::AffiliateProduct.upsert_from_feed!(
      source: "tradedoubler", external_id: "up1", title: "Ny tittel",
      click_url: "https://example.test/a", price_cents: 2_000
    )

    assert_equal first.id, second.id
    assert_equal "Ny tittel", second.title
    assert_equal 2_000, second.price_cents
    assert_equal 1, Shared::AffiliateProduct.where(source: "tradedoubler", external_id: "up1").count
  end

  # last_seen_at is how `fresh` tells live inventory from withdrawn inventory,
  # so a re-import must refresh it even when no other attribute changed.
  test "upsert_from_feed! refreshes last_seen_at on an unchanged row" do
    product = Shared::AffiliateProduct.upsert_from_feed!(
      source: "tradedoubler", external_id: "same", title: "Same",
      click_url: "https://example.test/s"
    )
    product.update_column(:last_seen_at, 30.days.ago)

    Shared::AffiliateProduct.upsert_from_feed!(
      source: "tradedoubler", external_id: "same", title: "Same",
      click_url: "https://example.test/s"
    )

    refute product.reload.stale?
  end

  test "sellable excludes stale and out-of-stock rows" do
    live = build_product(external_id: "live")
    live.save!
    stale = build_product(external_id: "stale")
    stale.save!
    stale.update_column(:last_seen_at, 30.days.ago)
    gone = build_product(external_id: "gone", in_stock: false)
    gone.save!

    ids = Shared::AffiliateProduct.sellable.pluck(:external_id)
    assert_includes ids, "live"
    refute_includes ids, "stale"
    refute_includes ids, "gone"
  end

  test "real excludes placeholder inventory" do
    build_product(external_id: "r", placeholder: false).save!
    build_product(external_id: "p", placeholder: true).save!

    assert_equal [ "r" ], Shared::AffiliateProduct.real.pluck(:external_id)
  end

  # A product licensed for one market must not surface on another domain; a nil
  # market is treated as global so an unreported market still renders.
  test "for_market matches the market or global rows" do
    build_product(external_id: "no", market: "NO").save!
    build_product(external_id: "us", market: "US").save!
    build_product(external_id: "global", market: nil).save!

    ids = Shared::AffiliateProduct.for_market("NO").pluck(:external_id)
    assert_includes ids, "no"
    assert_includes ids, "global"
    refute_includes ids, "us"
  end

  test "price renders minor units as a decimal string" do
    assert_equal "149.90", build_product(price_cents: 14_990).price
    assert_nil build_product(price_cents: nil).price
  end

  test "placeholder seeding is idempotent and always flagged" do
    first = Brgen::AffiliatePlaceholders.seed!
    assert_operator first, :>, 0
    Brgen::AffiliatePlaceholders.seed!

    assert_equal first, Shared::AffiliateProduct.where(placeholder: true).count, "re-seeding must upsert, not duplicate"
    assert_equal 0, Shared::AffiliateProduct.real.count, "placeholders must never count as real inventory"
  end
end
