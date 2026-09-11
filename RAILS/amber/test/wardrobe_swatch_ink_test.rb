# frozen_string_literal: true

require "test_helper"
require_relative "../../gates/support/design_metrics/contrast"

# The swatch stands in for a missing photograph, so it is the garment's own
# colour and carries the item's initial over it. One ink cannot serve ten
# colours: against --text (#333333) charcoal measured 1.21, navy 1.36, tortoise
# 2.26 and terracotta 3.42, all under the 4.5 floor for the 18px name they
# carry, while the note beside the rule said the swatches were "chosen light
# enough to carry it".
#
# The map in ApplicationHelper now pairs each swatch with an ink, and the pairs
# are checked here rather than restated: this asks Deploy::DesignMetrics::Contrast,
# which is the one implementation of WCAG relative luminance in this repo that
# does the gamma decode. Writing the ratios into the helper by hand would be a
# second source for a number nobody would recompute.
class WardrobeSwatchInkTest < ActiveSupport::TestCase
  include ApplicationHelper

  FLOOR = 4.5

  # One colour word per branch, plus a word matching nothing so the default
  # pair is covered too.
  COLOURS = %w[navy charcoal ivory blush sage terracotta camel nude tortoise chartreuse].freeze

  def contrast
    @contrast ||= Object.new.extend(Deploy::DesignMetrics::Contrast)
  end

  test "every swatch carries an ink that clears the floor" do
    COLOURS.each do |colour|
      swatch = wardrobe_color_swatch(colour)
      ink = wardrobe_swatch_ink(colour)
      ratio = contrast.contrast_ratio(swatch, ink)

      assert_not_nil ratio, "#{colour}: #{swatch} against #{ink} did not parse"
      assert_operator ratio, :>=, FLOOR,
                      "#{colour}: #{ink} on #{swatch} is #{ratio.round(2)}, under #{FLOOR}"
    end
  end

  # The pair is chosen, not merely adequate: an ink that clears the floor while
  # the other one clears it by more is the wrong half of the map.
  test "each swatch takes whichever ink sits further from it" do
    COLOURS.each do |colour|
      swatch = wardrobe_color_swatch(colour)
      chosen = wardrobe_swatch_ink(colour)
      other = chosen == "#111111" ? "#ffffff" : "#111111"

      assert_operator contrast.contrast_ratio(swatch, chosen), :>=,
                      contrast.contrast_ratio(swatch, other),
                      "#{colour}: #{other} reads better on #{swatch} than the #{chosen} the map picks"
    end
  end

  # Both readers come off one map, so a colour added to the swatch list cannot
  # arrive without an ink.
  test "the two readers agree on the same entry" do
    COLOURS.each do |colour|
      assert_equal [wardrobe_color_swatch(colour), wardrobe_swatch_ink(colour)],
                   wardrobe_swatch_pair(colour)
    end
  end
end
