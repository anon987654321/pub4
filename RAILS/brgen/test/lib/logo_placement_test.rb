# frozen_string_literal: true

require "test_helper"

# The city wordmark must land in exactly the same place on every brgen surface.
# It did not: playlist overrode top, inset-inline-start, padding, min-height,
# min-width and font-size, putting the mark at (6, 4) 53x23 against (14, 9)
# 63x44 everywhere else — a visible jump when moving between verticals.
#
# Asserted against the stylesheet rather than a rendered page because the
# offending rules were body.vertical-* overrides, and a request spec only ever
# exercises one surface at a time.
class LogoPlacementTest < ActiveSupport::TestCase
  STYLESHEETS = Rails.root.glob("app/assets/stylesheets/*.scss").freeze

  # Anything that moves or resizes the mark. Colour and z-index are fine: a
  # vertical may need to win a stacking contest or invert on its own backdrop.
  PLACEMENT = %w[
    top bottom left right inset inset-block-start inset-inline-start
    padding margin min-height min-width width height
    font-size font-weight letter-spacing position transform
  ].freeze

  def logo_override_declarations
    STYLESHEETS.flat_map do |path|
      source = path.read
      # body.vertical-x .brgen-logo-mark { ... } — the surface-scoped ones only.
      source.scan(/^\s*body\.vertical-[\w-]+[^{]*\.brgen-logo-mark[^{]*\{([^}]*)\}/m).flat_map do |(body)|
        body.scan(/^\s*([a-z-]+)\s*:/).flatten.map { |prop| [ path.basename.to_s, prop ] }
      end
    end
  end

  def test_no_vertical_moves_or_resizes_the_wordmark
    offenders = logo_override_declarations.select { |(_file, prop)| PLACEMENT.include?(prop) }

    assert_empty offenders.map { |file, prop| "#{file}: #{prop}" },
                 "the wordmark must sit in the same spot on every surface"
  end

  # The layout renders it once, unconditionally, outside any vertical guard —
  # so every surface gets one and only one.
  #
  # Asserted through the shared partial rather than the class literal. The mark
  # moved into shared/_brand_mark so brgen, amber and bsdports render the same
  # one: brgen had a fixed wordmark, amber a non-fixed SVG, bsdports none at all
  # (and, once counted, three separate links home). brgen still passes
  # .brgen-logo-mark alongside .brand-mark, so every rule already written against
  # it keeps applying — but the class name is now an argument, not markup, and a
  # test that greps for the literal was testing the spelling.
  def test_layout_renders_exactly_one_wordmark
    layout = Rails.root.join("app/views/layouts/application.html.erb").read

    assert_equal 1, layout.scan(%r{render "shared/brand_mark"}).size
    assert_includes layout, "brgen-logo-mark"
  end

  # Unconditional: no vertical, auth or guest branch may skip it.
  def test_the_wordmark_is_not_behind_a_conditional
    layout = Rails.root.join("app/views/layouts/application.html.erb").read
    line = layout.lines.find { |l| l.include?('render "shared/brand_mark"') }

    refute_nil line
    refute_match(/\bif\b|\bunless\b/, line,
                 "the mark must render on every surface, not behind a guard")
  end
end
