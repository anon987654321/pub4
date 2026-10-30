# frozen_string_literal: true

require "fileutils"
require_relative "test_helper"
require "review/scan/law_tree"
require_relative "../lib/fix/scan/ast_fixer"

# One scale for the ratchet, the two scale Laws and their /fix repair. The
# property that matters is agreement: whatever EIGHT_PX_RHYTHM or
# LINE_HEIGHT_ON_SCALE reports, snap_to_design_scale clears, and what it leaves
# the Laws do not report again.
class TestDesignScale < Minitest::Test
  SCALE = Master::Design::Scale.new(Master.tokens.fetch("scale"))

  def test_off_scale_lengths_read_units_and_skip_computed_parts
    assert_equal %w[6px 10px], SCALE.off_scale_lengths("6px 10px")
    assert_empty SCALE.off_scale_lengths("1px 0 auto")
    assert_empty SCALE.off_scale_lengths("0.75rem -8px")
    assert_empty SCALE.off_scale_lengths("calc(var(--x) + 3px)")
  end

  def test_nearest_breaks_a_tie_toward_the_smaller_step
    assert_equal 48.0, SCALE.nearest(52)
    assert_equal 4.0, SCALE.nearest(6)
    assert_equal 8.0, SCALE.nearest(7)
  end

  def test_snap_keeps_the_unit_sign_and_hairline
    assert_equal "8px 12px", SCALE.snap("padding", "7px 11px")
    assert_equal "-8px", SCALE.snap("margin", "-7px")
    assert_equal "0.5rem", SCALE.snap("gap", "0.4rem")
    assert_nil SCALE.snap("margin", "1px 0")
    assert_nil SCALE.snap("padding", "calc(100% - 3px)")
    assert_nil SCALE.snap("width", "10px")
  end

  def test_snap_moves_an_off_scale_line_height_and_leaves_an_absolute_one
    assert_equal "1.4", SCALE.snap("line-height", "1.45")
    assert_nil SCALE.snap("line-height", "1.5")
    assert_nil SCALE.snap("line-height", "20px")
    assert_equal :absolute, SCALE.line_height_kind("20px")
  end

  def test_fix_clears_what_the_laws_report
    source = <<~SCSS
      .card {
        padding: 7px 11px;
        margin: -7px 0 1px;
        gap: 0.4rem;
        line-height: 1.45;
      }
    SCSS
    refute_empty findings(source)

    result = fix(source)
    content = result[:content]

    assert_includes result[:transforms], :design_scale
    snapped = ["padding: 8px 12px;", "margin: -8px 0 1px;", "gap: 0.5rem;", "line-height: 1.4;"]
    snapped.each { |want| assert_includes content, want }
    assert_empty findings(content)
  end

  def test_fix_leaves_comments_opt_outs_computed_values_and_tokens
    source = <<~SCSS
      /* padding: 10px; is the old value */
      // margin: 6px;
      .a {
        /* scale: ok */
        padding: 10px;
        margin: calc(var(--gutter) + 3px);
        --space-odd: 10px;
      }
    SCSS
    result = fix(source)

    assert_equal source, result[:content]
    refute_includes result[:transforms], :design_scale
  end

  def test_fix_is_idempotent
    once = fix(".b { padding: 10px; line-height: 1.3; }\n")[:content]

    assert_equal once, fix(once)[:content]
  end

  private

  def findings(source)
    %i[EIGHT_PX_RHYTHM LINE_HEIGHT_ON_SCALE].flat_map do |id|
      Law.definitions.fetch(id).scan(source, file: "/repo/app/assets/stylesheets/_card.scss")
    end
  end

  def fix(content)
    Dir.mktmpdir do |dir|
      path = File.join(dir, "app", "assets", "stylesheets", "_card.scss")
      FileUtils.mkdir_p(File.dirname(path))
      File.write(path, content)
      result = Master::Fix::Scan::AstFixer.fix(path, content)
      { content: File.read(path), transforms: result.transforms }
    end
  end
end
