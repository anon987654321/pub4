# frozen_string_literal: true

require "minitest/autorun"

class SurfaceMicroRefinementContractTest < Minitest::Test
  ROOT = File.expand_path("..", __dir__)
  SHEET = File.join(ROOT, "shared/app/assets/stylesheets/_surface_micro_refinements.scss")
  MATRIX = File.join(ROOT, "shared/SURFACE_MICRO_REFINEMENT_MATRIX.md")
  STACKS = %w[
    shared/app/assets/stylesheets/_stack.scss
    shared/app/assets/stylesheets/_stack_brgen.scss
  ].freeze

  def test_sheet_has_exactly_288_marked_refinements
    source = File.read(SHEET, encoding: "UTF-8")
    assert_equal 288, source.scan(/\/\* srf:\d{3} \*\//).size
  end

  def test_matrix_has_exactly_288_items
    source = File.read(MATRIX, encoding: "UTF-8")
    assert_equal 288, source.lines.count { |line| line.match?(/^\d{3}\. /) }
  end

  def test_shared_stacks_forward_the_surface_pass
    STACKS.each do |relative|
      source = File.read(File.join(ROOT, relative), encoding: "UTF-8")
      assert_includes source, '@forward "surface_micro_refinements";'
    end
  end

  def test_pass_targets_requested_surfaces_and_removes_box_chrome
    source = File.read(SHEET, encoding: "UTF-8")
    assert_includes source, ".nearby-chat-widget-panel"
    assert_includes source, ".radio-track-card"
    assert_includes source, ".bol-market-hero"
    assert_includes source, ".store-buybox"
    assert_includes source, "border: 0;"
    refute_includes source, "box-shadow: 0 "
  end
end
