# frozen_string_literal: true

require "minitest/autorun"

class SurfaceMicroRefinementTwoContractTest < Minitest::Test
  ROOT = File.expand_path("..", __dir__)
  SHEET = File.join(ROOT, "__shared/app/assets/stylesheets/_surface_micro_refinements_two.scss")
  STACKS = %w[
    __shared/app/assets/stylesheets/_stack.scss
    __shared/app/assets/stylesheets/_stack_brgen.scss
  ].freeze

  def test_marked_refinements_are_contiguous
    source = File.read(SHEET, encoding: "UTF-8")
    ids = source.lines.filter_map do |line|
      value = line.split("srf2:", 2)[1]
      value && value.split("*/", 2).first.to_i
    end
    assert_equal (1..496).to_a, ids
    assert_includes source, "ARCHIVED EXPERIMENTAL SURFACE PASS II"
  end

  def test_production_stacks_do_not_load_the_secondary_experiment
    STACKS.each do |relative|
      source = File.read(File.join(ROOT, relative), encoding: "UTF-8")
      refute_includes source, '@forward "surface_micro_refinements_two";'
    end
  end

  def test_requested_secondary_surfaces_are_present
    source = File.read(SHEET, encoding: "UTF-8")
    %w[.ad-slot .store-promo .amber-message .item-card .listing-step .cart-item .playlist-comment .radio-now-playing].each do |selector|
      assert_includes source, selector
    end
    refute_includes source, "box-shadow: 0 "
  end
end
