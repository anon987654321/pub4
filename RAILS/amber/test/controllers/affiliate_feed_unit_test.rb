# frozen_string_literal: true

require "test_helper"

# amber had AffiliateLink — a URL an owner pastes onto one wardrobe item — and
# no network inventory, so there was nothing to place between posts. These pin
# that the shared band actually renders here, because a partial that is moved
# but never reached is the failure this whole move was for.
class AffiliateFeedUnitTest < ActionDispatch::IntegrationTest
  FEED_EVERY = Shared::AffiliateHelper::FEED_EVERY

  def seed_products(count, category: "fashion")
    count.times do |i|
      Shared::AffiliateProduct.create!(
        source: "tradedoubler", external_id: "fixture-#{category}-#{i}",
        title: "Linen shirt #{i}", click_url: "https://example.test/p/#{i}",
        category: category, market: "NO", in_stock: true,
        placeholder: false, last_seen_at: Time.current
      )
    end
  end

  def sign_in_as(email)
    user = User.strict_loading(false).create!(email_address: email, password: "password")
    post session_path, params: { email_address: user.email_address, password: "password" }
    user
  end

  # The feed is behind authentication, so seeding signs in as its author.
  def seed_posts(count)
    user = sign_in_as("feed-#{SecureRandom.hex(4)}@example.test")
    count.times { |i| Post.create!(user: user, body: "Outfit #{i}") }
  end

  def test_the_band_renders_between_posts_once_there_is_inventory
    seed_products(4)
    seed_posts(FEED_EVERY + 1)

    get feed_posts_url

    assert_response :success
    assert_includes response.body, "affiliate_feed_unit"
    assert_includes response.body, "affiliate_feed_grid"
  end

  # The unit reads the shared locale file. Until the engine loaded every locale
  # rather than social.<locale>.yml literally, affiliate.en.yml sat on disk
  # unread and this rendered translation-missing spans in the app it moved for.
  def test_the_bands_strings_resolve_rather_than_reporting_missing
    seed_products(4)
    seed_posts(FEED_EVERY + 1)

    get feed_posts_url

    assert_not_includes response.body, "translation missing"
    assert_includes response.body, I18n.t("affiliate.sponsored")
  end

  # An electronics deal between two outfits reads as a banner; a garment reads
  # as the app working. The category filter is the difference.
  def test_inventory_outside_the_category_is_not_shown
    seed_products(4, category: "electronics")
    seed_posts(FEED_EVERY + 1)

    get feed_posts_url

    assert_response :success
    assert_not_includes response.body, "affiliate_feed_grid"
  end

  # A band in the last slot reads as the end of the feed.
  def test_a_feed_shorter_than_the_cadence_gets_no_band
    seed_products(4)
    seed_posts(FEED_EVERY)

    get feed_posts_url

    assert_response :success
    assert_not_includes response.body, "affiliate_feed_grid"
  end

  def test_no_inventory_renders_no_band_rather_than_an_empty_one
    seed_posts(FEED_EVERY + 1)

    get feed_posts_url

    assert_response :success
    assert_not_includes response.body, "affiliate_feed_unit"
  end
end
