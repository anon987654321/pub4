# frozen_string_literal: true

require "minitest/autorun"

# A rem inside an SVG viewBox does not mean what the type scale thinks it means.
#
# `ui_polish.type_tokens` says a px font-size cannot participate in the modular
# scale, and it is right about document text. It is wrong about text drawn inside
# a viewBox: there a length is a fraction of the SVG's own coordinate grid, and
# swapping px for a rem token silently reparents that glyph to the *root*
# font-size instead.
#
# That is not theoretical. amber's logotype (_logo.html.erb, viewBox 0 0 1000
# 500) had .amber-logo-mark on var(--text-xs)/var(--text-xl) while
# .amber-logo-word stayed on px. _minimal.scss raises the root from 16px to 21px
# at min-width 1280, so above that breakpoint the (r) grew from 12 to 15.75 user
# units against a word fixed at 60 — the mark/word ratio moving 0.2000 -> 0.2625,
# measured in Chrome at 1400px wide. It read as a safe swap because at the
# default root size 0.75rem is exactly 12px, so nothing moves until the viewport
# crosses 1280.
#
# Hence this test rather than a note in a doc: the swap is invisible in review,
# invisible at default width, and an autofix pass will make it again.
class SvgTypeScaleTest < Minitest::Test
  ROOT = File.expand_path("..", __dir__)

  # Selector fragments that scope into an element carrying a viewBox. CSS cannot
  # tell us this — the viewBox is in the markup — so the list is explicit. Add a
  # row when a new SVG gets its own text styling.
  VIEWBOX_SCOPES = [
    ".amber-logo-svg",
  ].freeze

  RELATIVE_UNIT = /\b\d*\.?\d+(rem|em)\b|var\(\s*--text-/

  def stylesheets
    @stylesheets ||= %w[shared brgen amber bsdports].flat_map do |app|
      Dir.glob(File.join(ROOT, app, "app/assets/stylesheets/**/*.scss")) +
        Dir.glob(File.join(ROOT, app, "engines/*/app/assets/stylesheets/**/*.scss"))
    end.reject { |path| path.include?("/vendor/") || path.include?("/public/") }.sort
  end

  def test_stylesheets_are_actually_being_read
    refute_empty stylesheets, "found no stylesheets to check — the glob is wrong, not the tree"
    assert stylesheets.any? { |p| File.basename(p) == "_brand.scss" && p.include?("/amber/") },
           "amber/_brand.scss is the file this test exists for and the glob did not reach it"
  end

  def test_font_size_inside_a_viewbox_scope_is_absolute
    offenders = []

    stylesheets.each do |path|
      selector = nil
      File.readlines(path).each_with_index do |line, index|
        selector = line if line.include?("{")
        next unless line =~ /font-size\s*:/
        next unless VIEWBOX_SCOPES.any? { |scope| selector.to_s.include?(scope) }
        next unless line.match?(RELATIVE_UNIT)

        offenders << "#{path.delete_prefix("#{ROOT}/")}:#{index + 1} — #{line.strip}"
      end
    end

    assert_empty offenders, <<~MSG.strip
      font-size inside an SVG viewBox must be absolute:

        #{offenders.join("\n  ")}

      A rem here resolves against the root font-size, which _minimal.scss changes
      at min-width 1280 — so this glyph will grow relative to the rest of the
      artwork above that width and only above it. Use px; the viewBox already
      scales the whole mark.
    MSG
  end
end
