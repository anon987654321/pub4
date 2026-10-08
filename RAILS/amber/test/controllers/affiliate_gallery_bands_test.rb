# frozen_string_literal: true

require "test_helper"

# The wardrobe and the outfit gallery are CSS grids, not vertical lists, so the
# band needs the in_grid modifier to span the row rather than be laid out as one
# more garment tile. These pin the placement and that modifier, because getting
# it wrong is invisible to a test that only asserts the markup is present.
class AffiliateGalleryBandsTest < ActionDispatch::IntegrationTest
  FEED_EVERY = Shared::AffiliateHelper::FEED_EVERY

  def sign_in_as(email)
    user = User.strict_loading(false).create!(email_address: email, password: "password")
    post session_path, params: { email_address: user.email_address, password: "password" }
    user
  end

  def seed_products(count, category: "fashion")
    count.times do |i|
      Shared::AffiliateProduct.create!(
        source: "tradedoubler", external_id: "gallery-#{category}-#{i}",
        title: "Wool coat #{i}", click_url: "https://example.test/g/#{i}",
        category: category, market: "NO", in_stock: true,
        placeholder: false, last_seen_at: Time.current
      )
    end
  end

  def seed_items(user, count)
    count.times { |i| Item.create!(user: user, title: "Garment #{i}", category: Item::CATEGORIES.first) }
  end

  def test_the_wardrobe_grid_carries_the_band_between_garments
    user = sign_in_as("wardrobe-band@example.test")
    seed_products(4)
    seed_items(user, FEED_EVERY + 1)

    get items_url

    assert_response :success
    assert_includes response.body, "affiliate_feed_unit"
  end

  # Without this the aside is sized as a garment tile and the packed band inside
  # it collapses. The class is the whole reason the placement works.
  def test_the_band_spans_the_grid_row_rather_than_sitting_in_it
    user = sign_in_as("wardrobe-span@example.test")
    seed_products(4)
    seed_items(user, FEED_EVERY + 1)

    get items_url

    assert_includes response.body, "affiliate_feed_unit--in_grid"
  end

  def test_a_wardrobe_shorter_than_the_cadence_gets_no_band
    user = sign_in_as("wardrobe-short@example.test")
    seed_products(4)
    seed_items(user, FEED_EVERY)

    get items_url

    assert_response :success
    assert_not_includes response.body, "affiliate_feed_unit"
  end

  def test_the_outfit_gallery_uses_the_same_cadence_and_modifier
    user = sign_in_as("outfits-band@example.test")
    seed_products(4)
    (FEED_EVERY + 1).times { |i| Outfit.create!(user: user, name: "Look #{i}") }

    get outfits_url

    assert_response :success
    assert_includes response.body, "affiliate_feed_unit--in_grid"
  end

  # brgen's feed is a vertical list; the modifier there would span a grid that
  # does not exist. The local is opt-in for exactly that reason.
  def test_the_modifier_is_opt_in_rather_than_always_on
    user = sign_in_as("feed-plain@example.test")
    seed_products(4)
    (FEED_EVERY + 1).times { |i| Post.create!(user: user, body: "Outfit note #{i}") }

    get feed_posts_url

    assert_includes response.body, "affiliate_feed_unit"
    assert_not_includes response.body, "affiliate_feed_unit--in_grid"
  end
end
