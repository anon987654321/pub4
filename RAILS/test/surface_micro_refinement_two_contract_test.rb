# frozen_string_literal: true

require "minitest/autorun"

class SurfaceMicroRefinementTwoContractTest < Minitest::Test
  ROOT = File.expand_path("..", __dir__)
  SHEET = File.join(ROOT, "shared/app/assets/stylesheets/_surface_micro_refinements_two.scss")

  def test_marked_refinements_are_contiguous
    source = File.read(SHEET, encoding: "UTF-8")
    ids = source.lines.filter_map do |line|
      value = line.split("srf2:", 2)[1]
      value && value.split("*/", 2).first.to_i
    end
    assert_equal (1..496).to_a, ids
  end

  def test_requested_secondary_surfaces_are_present
    source = File.read(SHEET, encoding: "UTF-8")
    %w[.ad-slot .store-promo .amber-message .item-card .listing-step .cart-item .playlist-comment .radio-now-playing].each do |selector|
      assert_includes source, selector
    end
    refute_includes source, "box-shadow: 0 "
  end
end
