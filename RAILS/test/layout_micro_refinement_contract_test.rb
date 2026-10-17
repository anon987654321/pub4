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
    __shared/app/assets/stylesheets/_stack.scss
    __shared/app/assets/stylesheets/_stack_brgen.scss
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

  def test_micro_layout_refinements_are_mobile_first_and_restore_wide_measures
    sheet = File.read(File.join(ROOT, "__shared/app/assets/stylesheets/_layout_micro_refinements.scss"), encoding: "UTF-8")
    mobile, wide = sheet.split("@media (min-width: 768px)", 2)

    refute_match(/@media\s*\(\s*max-width\b/, sheet,
                 "compact layout rules must be the base, not a max-width override")
    assert_includes mobile, 'body[data-layout-pass="micro-320"] {'
    assert_match(/body\[data-layout-pass="micro-320"\]\s*\{[^}]*text-wrap:\s*pretty;/m, mobile)
    assert_match(/body\[data-layout-pass="micro-320"\]\s*\.page-header\s*\{[^}]*max-inline-size:\s*var\(--measure\);/m, wide)
    assert_match(/body\[data-layout-pass="micro-320"\]\s*\.page-actions/ , mobile)
    assert_match(/body\[data-layout-pass="micro-320"\]\s*\.page-actions[\s\S]*?max-inline-size:\s*none;/m, wide)
    assert_match(/body\[data-layout-pass="micro-320"\]\.vertical-marketplace\s+\.storefront-bol-mainnav\s*\{[^}]*max-inline-size:\s*var\(--bol-max\);/m, wide)
    assert_match(/body\[data-layout-pass="micro-320"\]\s*#sections[\s\S]*?max-inline-size:\s*none;/m, wide)
    assert_match(/body\[data-layout-pass="micro-320"\]\s*\{[^}]*text-wrap:\s*balance;/m, wide)
  end

  def test_matrix_and_sheet_keep_the_same_refinement_count
    matrix = File.read(File.join(ROOT, "__shared/LAYOUT_MICRO_REFINEMENT_MATRIX.md"), encoding: "UTF-8")
    sheet = File.read(File.join(ROOT, "__shared/app/assets/stylesheets/_layout_micro_refinements.scss"), encoding: "UTF-8")

    sequence = matrix.lines.filter_map { |line| line[/\A(\d{3})\./, 1] }
    assert_equal (1..343).map { |n| format("%03d", n) }, sequence,
                 "the matrix must contain all 343 numbered refinements exactly once"
    assert_includes sheet, "343 concrete property refinements"
    refute_includes sheet, "@include micro-layout-refinements"
  end
end
