# frozen_string_literal: true

require "test_helper"

class BrgenVerticalPromoTest < ActiveSupport::TestCase
  test "first-party promo replaces every third commercial slot" do
    assert_not Brgen::HomeFeed.promotion_slot?(2)
    assert_not Brgen::HomeFeed.promotion_slot?(4)
    assert Brgen::HomeFeed.promotion_slot?(6)
    assert_not Brgen::HomeFeed.promotion_slot?(8)
    assert Brgen::HomeFeed.promotion_slot?(12)

    assert_equal :radio, Brgen::HomeFeed.promotion_for(6)
    assert_equal :marketplace, Brgen::HomeFeed.promotion_for(12)
    assert_equal :takeaway, Brgen::HomeFeed.promotion_for(18)
  end

  test "feed and infinite scroll both use the first-party promo seam" do
    feed = File.read(File.expand_path("../../brgen/lib/brgen/home_feed.rb", __dir__))
    view = File.read(File.expand_path("../../brgen/app/views/home/_live_search_results.html.erb", __dir__))
    partial = File.read(File.expand_path("../../brgen/app/views/home/_vertical_promo_unit.html.erb", __dir__))
    reflex = File.read(File.expand_path("../../brgen/app/reflexes/home_infinite_scroll_reflex.rb", __dir__))
    locales = File.read(File.expand_path("../../brgen/config/locales/promo.en.yml", __dir__))

    assert_includes feed, "PROMOTION_EVERY = AFFILIATE_EVERY * 3"
    assert_includes feed, "VERTICAL_PROMOTIONS"
    assert_includes view, 'render "home/vertical_promo_unit"'
    assert_includes reflex, 'partial: "home/vertical_promo_unit"'
    assert_includes partial, 't("promo.radio.kicker")'
    assert_includes locales, "Spin for the win!"
  end

  test "promo css preserves the source rotation without a third-party animation library" do
    css = File.read(File.expand_path("../../brgen/app/assets/stylesheets/_vertical_promo.scss", __dir__))

    assert_includes css, "rotate(3000deg)"
    assert_includes css, "100s linear infinite"
    assert_includes css, "@media (prefers-reduced-motion: reduce)"
    refute_includes css, "anime"
    refute_includes css, "canvas"
  end
end
