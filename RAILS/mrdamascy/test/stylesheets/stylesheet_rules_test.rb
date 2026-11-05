# frozen_string_literal: true

require "test_helper"

# Rules the stylesheets keep, read from the partials' source: an instrument
# of spelling, not a render (no browser here).
class StylesheetRulesTest < ActiveSupport::TestCase
  PARTIALS = Rails.root.glob("app/assets/stylesheets/_*.scss").to_h { |path| [ path.basename.to_s, path.read ] }

  test "hover backgrounds belong to pointers that hover" do
    lines = rules_outside("(hover: hover)").map(&:last)
    stuck = lines.select { |line| line.include?(":hover") && !line.start_with?("//") }

    assert_empty stuck
  end

  test "filled buttons and chips keep an edge in forced colours" do
    block = PARTIALS.fetch("_buttons.scss")[/@media \(forced-colors: active\) \{.*?\n\}/m]

    assert block, "no forced-colors block"
    %w[.button-primary .button-vipps .button-stripe .button-reorder .chip].each do |selector|
      assert_includes block, selector
    end
    assert_includes block, "ButtonText"
  end

  test "motion and layers come from tokens" do
    sources = PARTIALS.except("_tokens.scss")

    assert_empty sources.filter_map { |name, source| name if source.match?(/\d+ms ease\b/) }, "raw motion"
    assert_empty sources.filter_map { |name, source| name if source.match?(/z-index: (?!1;)\d/) }, "raw layers"
    assert_includes PARTIALS.fetch("_base.scss"), "top: calc(var(--brand-bar-height) + var(--space-16)"
    assert_includes PARTIALS.fetch("_menu.scss"), "top: var(--brand-bar-height);"
  end

test "spacing takes the scale, not raw pixels" do
    spacing = /^\s*(?:padding[\w-]*|margin[\w-]*|gap|row-gap|column-gap|inset[\w-]*|top|bottom|left|right):([^;]+);/
    raw = PARTIALS.except("_tokens.scss").flat_map do |name, source|
      source.scan(spacing).flatten.grep(/(?<![\w.])[1-9]\d*px/).map { |value| "#{name}:#{value.strip}" }
    end

    assert_empty raw
  end

  test "titles balance their lines and amounts use tabular figures" do
    assert_match(/\.page-title \{[^}]*text-wrap: balance;/, PARTIALS.fetch("_base.scss"))
    numerals = PARTIALS.fetch("_base.scss")[/((?:\.[\w-]+,\n)+\.[\w-]+) \{\n  font-variant-numeric: tabular-nums;/, 1]
    assert numerals, "no tabular-nums rule"
    %w[.item-price .sheet-total .line-sum .totals .cart-bar-meta .board-count].each do |selector|
      assert_includes numerals, selector
    end
  end

  private

  # Each top-level block of a partial with the media query it sits in.
  def rules_outside(media)
    PARTIALS.flat_map { |name, source| top_level_lines(source, media).map { |line| [ name, line ] } }
  end

  def top_level_lines(source, media)
    depth = 0
    inside = false
    source.each_line.filter_map do |line|
      inside = true if depth.zero? && line.start_with?("@media #{media}")
      found = line.strip if depth.zero? && !inside

      depth += line.count("{") - line.count("}")
      inside = false if depth.zero?
      found
    end
  end
end
