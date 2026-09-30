# frozen_string_literal: true

require "minitest/autorun"

class LayoutMicroRefinementContractTest < Minitest::Test
  ROOT = File.expand_path("..", __dir__)

  LAYOUTS = %w[
    ../amber/app/views/layouts/application.html.erb
    ../brgen/app/views/layouts/application.html.erb
    ../bsdports/app/views/layouts/application.html.erb
  ].freeze

  SHARED_STACKS = %w[
    shared/app/assets/stylesheets/_stack.scss
    shared/app/assets/stylesheets/_stack_brgen.scss
  ].freeze

  def test_browser_layouts_opt_into_the_micro_refinement_pass
    LAYOUTS.each do |relative|
      source = File.read(File.expand_path(relative, ROOT), encoding: "UTF-8")
      assert_includes source, 'data-layout-pass="micro-320"'
    end
  end

  def test_both_shared_stacks_load_the_canonical_refinement_sheet
    SHARED_STACKS.each do |relative|
      source = File.read(File.expand_path(relative, ROOT), encoding: "UTF-8")
      assert_includes source, '@forward "layout_micro_refinements";'
    end
  end

  def test_matrix_and_sheet_keep_the_same_refinement_count
    matrix = File.read(File.join(ROOT, "shared/LAYOUT_MICRO_REFINEMENT_MATRIX.md"), encoding: "UTF-8")
    sheet = File.read(File.join(ROOT, "shared/app/assets/stylesheets/_layout_micro_refinements.scss"), encoding: "UTF-8")

    assert_equal 343, matrix.lines.count { |line| line.match?(/^d{3}./) }
    assert_includes sheet, "343 concrete property refinements"
    refute_includes sheet, "@include micro-layout-refinements"
  end
end
