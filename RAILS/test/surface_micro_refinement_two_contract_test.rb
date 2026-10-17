# frozen_string_literal: true

require "minitest/autorun"

class SurfaceMicroRefinementTwoContractTest < Minitest::Test
  ROOT = File.expand_path("..", __dir__)
  SHEET = File.join(ROOT, "__shared/app/assets/stylesheets/_surface_micro_refinements_two.scss")
  MATRIX = File.join(ROOT, "__shared/SURFACE_MICRO_REFINEMENT_MATRIX_II.md")
  STACKS = %w[
    __shared/app/assets/stylesheets/_stack.scss
    __shared/app/assets/stylesheets/_stack_brgen.scss
  ].freeze

  def test_experimental_stylesheet_is_absent_and_matrix_is_archived
    refute File.exist?(SHEET),
           "the unvalidated second surface pass must not remain in the active stylesheet tree"
    matrix = File.read(MATRIX, encoding: "UTF-8")
    assert_includes matrix, "Archived surface micro-refinement matrix II"
    assert_equal 496, matrix.lines.count { |line| line.match?(/^\d{3}\. /) }
  end

  def test_production_stacks_do_not_load_the_secondary_experiment
    STACKS.each do |relative|
      source = File.read(File.join(ROOT, relative), encoding: "UTF-8")
      refute_includes source, '@forward "surface_micro_refinements_two";'
    end
  end

  def test_requested_secondary_surfaces_remain_documented_in_the_matrix
    source = File.read(MATRIX, encoding: "UTF-8")
    %w[.ad-slot .store-promo .amber-message .item-card .listing-step .cart-item .playlist-comment .radio-now-playing].each do |selector|
      assert_includes source, selector
    end
  end
end
