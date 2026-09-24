# frozen_string_literal: true

require "test_helper"

class PromotionalArtTest < ActiveSupport::TestCase
  test "builds deterministic image direction and separate exact copy" do
    art = Shared::PromotionalArt.build(
      product: ["blue commuter bicycle", "helmet"],
      headline: "A better ride for Bergen",
      body: "City-ready, easy to carry and built for wet roads.",
      price: "2 490 kr",
      badge: "Local offer",
      cta: "See offer"
    )

    assert_equal "hero", art.layout
    assert_equal "chalk", art.background
    assert_includes art.image_prompt, "no typography or marketing copy"
    assert_includes art.image_prompt, "matte background"
    assert_equal ["blue commuter bicycle", "helmet"], art.product
    assert_equal "2 490 kr", art.price
    assert_equal "32px", art.safe_inset
    assert_includes art.image_prompt, "no gradient, no glow, no decorative props"
  end

  test "rejects overlong campaign copy" do
    assert_raises(ArgumentError) do
      Shared::PromotionalArt.build(
        product: "rice cooker",
        headline: "a" * 55
      )
    end
  end

  test "rejects unknown layout and background" do
    assert_raises(ArgumentError) do
      Shared::PromotionalArt.build(product: "pizza", headline: "Tonight", layout: :poster)
    end
    assert_raises(ArgumentError) do
      Shared::PromotionalArt.build(product: "pizza", headline: "Tonight", background: :neon)
    end
  end
  test "caps a campaign at the canonical product count" do
    assert_raises(ArgumentError) do
      Shared::PromotionalArt.build(
        product: %w[a b c d e],
        headline: "Five is too many"
      )
    end
  end
end
