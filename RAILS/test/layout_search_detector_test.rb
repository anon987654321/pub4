# frozen_string_literal: true

require "minitest/autorun"
require_relative "../gates/support/layout_search"
require_relative "../gates/lib/research/layout_search"

# The gate's own fixture pair, the way every law in MASTER carries one: a
# tree-shape the detector must read as photo_first and one it must read as
# body_first. On 2026-08-21 the card_media extraction moved the deal-card-img
# marker into a partial and the source-reading detector called the unchanged
# page a layout regression — an instrument blinded by a refactor, found only
# because the gate went red. This pins both the detector and the one level of
# render expansion that fixed it.
class LayoutSearchDetectorTest < Minitest::Test
  def detect(card)
    Deploy::LayoutSearch.new.send(:detect_variant, "media_placement", { card: card })
  end

  def test_an_inline_image_slot_before_the_body_reads_photo_first
    assert_equal "photo_first", detect(<<~ERB)
      <div class="deal-card-img"><img></div>
      <div class="deal-card-body">x</div>
    ERB
  end

  def test_a_body_before_the_image_slot_reads_body_first
    assert_equal "body_first", detect(<<~ERB)
      <div class="deal-card-body">x</div>
      <div class="deal-card-img"><img></div>
    ERB
  end

  def test_the_real_card_reads_photo_first_through_the_render_expansion
    expanded = Deploy::LayoutSearchGate.new.send(:card_source)
    assert_includes expanded, "deal-card-img",
      "card_source must inline marketplace/_card_media so the marker is visible"
    assert_equal "photo_first", detect(expanded)
  end
end
