# frozen_string_literal: true

require "minitest/autorun"
require "yaml"
require "tempfile"
require_relative "../shared/lib/pub4/breakpoint_lint"

# OPENBSD/data/debt.yml, rails_no_breakpoint_token: colour, space, motion,
# elevation and the dialect maps are single-sourced; the viewport scale was not, so
# breakpoints were written by hand and drifted into 13 distinct widths across 58
# media queries.
class BreakpointLintTest < Minitest::Test
  L = Pub4::BreakpointLint

  def test_no_kind_exceeds_its_baseline
    findings = L.scan
    exceeded = L.over_baseline(findings)

    assert_empty exceeded,
                 "#{exceeded.join('; ')}\n" \
                 "#{findings.first(10).map { |f| "  #{f.file}:#{f.line} [#{f.kind}] #{f.value}" }.join("\n")}"
  end

  # A baseline that has been beaten and never lowered is a baseline nobody trusts.
  def test_baselines_are_not_stale
    counts = L.counts

    L::BASELINES.each do |kind, baseline|
      assert_equal baseline, counts.fetch(kind),
                   "#{kind} is at #{counts.fetch(kind)} against a baseline of #{baseline} — " \
                   "lower the baseline in breakpoint_lint.rb"
    end
  end

  # The whole point of the token: one number can never be both a floor and a
  # ceiling, because at that width both blocks match and bundle order decides.
  def test_no_width_is_both_a_floor_and_a_ceiling
    assert_empty L.ambiguous_pixels,
                 "these widths are used as both min-width and max-width somewhere in the " \
                 "family, so at exactly those widths two blocks match: " \
                 "#{L.ambiguous_pixels.join(', ')}"
  end

  def test_the_token_list_is_the_source_and_is_not_empty
    viewport = YAML.safe_load_file(L::TOKENS).fetch("viewport")

    refute_empty viewport, "design_tokens.yml lost its viewport scale"
    assert_equal viewport.values.map { |v| Integer(v) }.sort, L.edges,
                 "the lint must read the tokens, not carry its own copy"
  end

  # Every media query in the tree resolves to a declared edge or an edge minus one,
  # apart from the three recorded above. Stated as the invariant so that fixing one
  # of the three is not a failure.
  def test_findings_are_a_subset_of_the_recorded_exceptions
    recorded = [
      "brgen/app/assets/stylesheets/_marketplace_nav_bar.scss",
      "shared/app/assets/stylesheets/_zen_shell.scss",
    ]
    unexpected = L.scan.map(&:file).uniq - recorded

    assert_empty unexpected, "new breakpoint drift in: #{unexpected.join(', ')}"
  end

  # A rule and the paragraph explaining the rule contain the same words. The first
  # run of this lint reported shared/_responsive.scss, whose header explains why a
  # rule is no longer wrapped in a media query it quotes.
  def test_a_media_query_inside_a_comment_is_not_a_bound
    scss = <<~SCSS
      // This used to be wrapped in @media (max-width: 640px), which collided.
      /* Also not a bound: @media (min-width: 640px) */
      .a { color: red; }
      @media (min-width: 480px) { .b { color: blue; } }
    SCSS
    Tempfile.create(["breakpoints", ".scss"]) do |file|
      file.write(scss)
      file.flush
      bounds = L.source_lines(file.path).join.scan(L::QUERY)

      assert_equal 1, bounds.size, "only the real query should survive comment stripping"
      assert_equal %w[min 480 px], bounds.first
    end
  end

  # Line numbers must survive comment blanking, or every finding points at the
  # wrong line and the lint is unusable even when it is right.
  def test_comment_stripping_preserves_line_numbers
    scss = "/* one\n   two\n   three */\n@media (min-width: 480px) { .a { color: red; } }\n"
    Tempfile.create(["breakpoints", ".scss"]) do |file|
      file.write(scss)
      file.flush
      lines = L.source_lines(file.path)

      assert_equal 4, lines.size
      assert_includes lines[3], "min-width: 480px"
    end
  end

  # rem in a media query resolves against the browser root (16px), not brgen's
  # 18px html size — this is the one place rem is not app-relative.
  def test_rem_bounds_are_converted_against_the_browser_root
    assert_equal 768.0, L.to_px("48", "rem")
    assert_equal 768.0, L.to_px("768", "px")
  end
end

