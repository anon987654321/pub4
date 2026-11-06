# frozen_string_literal: true

require "minitest/autorun"
require "yaml"
require "tmpdir"
require "fileutils"
require "stringio"
require_relative "../../OPENBSD/lib/check_result"
require_relative "../../MASTER/checks/lib/source/css_constitution"
require_relative "../../MASTER/checks/lib/source/css_brace_balance"
require_relative "../../MASTER/checks/support/design_metrics"
require_relative "../../MASTER/checks/lib/research/design_metrics"
require_relative "../../MASTER/checks/support/css_weight"
require_relative "../../MASTER/lib/operator/checks"
require_relative "support/check_live_and_css_budget_sources"

class CssBudgetRulesTest < Minitest::Test
  include CheckLiveAndCssBudgetSources

  # Exempt: an !important inside a reduced-motion block, which is the pattern
  # there rather than a lapse. Not exempt: every other !important in the same
  # stylesheet, such as the wordmark's armor, which is real debt.
  #
  # The sites are found by the rule they sit in rather than pinned by line. Two
  # pinned lines stood here and both had drifted onto lines carrying no
  # !important at all, so the exempt half asserted nothing while it passed.
  def test_reduced_motion_overrides_are_not_important_debt
    check = Deploy::CssConstitutionCheck.new
    check.run_once
    important = check.tally.fetch("important")

    rel = "brgen/app/assets/stylesheets/application.scss"
    source = File.read(File.join(Deploy::CssConstitutionCheck::RAILS, rel))
    motion, rest = Operator::ScssRules.rules(source).reject(&:at_rule?)
                                      .partition { |rule| rule.parents.any? { |parent| parent.include?("prefers-reduced-motion") } }
    sites = lambda do |rules|
      rules.flat_map do |rule|
        (rule.line..rule.end_line).select { |n| source.lines[n - 1].include?("!important") }.map { |n| "#{rel}:#{n}" }
      end
    end

    # The fixture above proves the exemption remains effective even when a
    # future reduced-motion rule contains !important; production need not carry
    # that debt merely to keep this test meaningful.
    # Every !important outside reduced motion stays counted. The file carries
    # none today, so test_reduced_motion_exception_stays_inside_its_media_block
    # is what proves the exemption cannot swallow one.
    assert_empty sites.call(motion) & important
    assert_empty sites.call(rest) - important, "the reduced-motion exemption has swallowed a non-motion !important"
  end

  def test_reduced_motion_exception_stays_inside_its_media_block
    check = Deploy::CssConstitutionCheck.new
    check.instance_variable_set(:@design, {})
    check.instance_variable_set(:@tally, { "important" => [], "rhythm" => [], "magic_hex" => [], "type_scale" => [], "weight_ladder" => [] })

    check.send(:count_budget_rules, "fixture.scss", "fixture.scss", <<~CSS)
      @media (prefers-reduced-motion: reduce) { .still { animation: none !important; } }
      .override { display: none !important; }
    CSS

    assert_equal ["fixture.scss:2"], check.tally.fetch("important")
  end

  # The rhythm budget, planted both ways: an off-rhythm px is counted, and the
  # same number in a line comment, a block comment's continuation line, or a
  # token fallback is not.
  def test_an_off_rhythm_px_is_counted_and_a_commented_one_is_not
    check = rhythm_check
    check.send(:count_budget_rules, "fixture.scss", "fixture.scss", <<~CSS)
      .card { padding: 13px; }
      .card { margin-top: -16px; gap: 24px; }
      // .old { padding: 13px; }
      /* The previous rule
         read padding: 13px here. */
      .tap { min-height: calc(var(--tap-min, 13px) + 4px); padding: var(--space-3, 13px); }
    CSS

    assert_equal ["fixture.scss:1 13px"], check.tally.fetch("rhythm")
  end

  def test_rhythm_over_its_ceiling_fails_the_check
    check = rhythm_check
    check.instance_variable_set(:@result, Deploy::CheckResult.new)
    check.instance_variable_set(:@budgets, { "rhythm" => 0 })
    check.send(:count_budget_rules, "fixture.scss", "fixture.scss", ".card { padding: 13px; }\n")
    check.send(:judge_budgets)
    result = check.instance_variable_get(:@result)

    assert_includes result.failures, "css_constitution rhythm: 1 exceeds ceiling 0 (+1) - fix them, or record a new ceiling with a reason"
  end

  # The magic-hex instrument counts colours in value position. A selector's
  # #name spells hex letters (#feed-panel, canvas#face), `#face {` opens a
  # rule, a token declaration is the palette's own definition, and a var()
  # fallback is the token's declared value — none of the four is a colour
  # painted at the call site. A real value still counts.
  def test_magic_hex_counts_values_and_not_selectors_or_declarations
    check = rhythm_check
    check.send(:count_budget_rules, "fixture.scss", "fixture.scss", <<~CSS)
      #feed-panel, #face-phosphor-trail { color: #ccc; }
      canvas#face { background: #000; }
      #face { opacity: .055; }
      .stage { background: var(--face-bg, #000); }
      :root { --accent: #1d9bf0; }
      .hero { background: #0a0a0a; color: #fff; }
    CSS

    assert_equal ["fixture.scss:1", "fixture.scss:2", "fixture.scss:6"], check.tally.fetch("magic_hex")
  end

  # A declaration the merge folded into an app's application.scss keeps the
  # exemption the old token files held, whether it stands alone or shares its
  # line with a selector — but a use-site on the same line is still counted.
  def test_a_token_declaration_is_exempt_wherever_the_merge_put_it
    check = rhythm_check
    check.send(:count_budget_rules, "fixture.scss", "fixture.scss", <<~CSS)
      :root {
        --sale: #F91906;
        --store-page: #ffffff;
      }
      .pill { --badge-fill: #123456; background: #654321; }
    CSS

    assert_equal ["fixture.scss:5"], check.tally.fetch("magic_hex")
  end

  def test_design_metrics_equal_contrast_ceiling_is_reported
    with_env("CHECK_AUTOFIX" => "0") do
      check = Deploy::DesignMetricsCheck.new
      check.instance_variable_set(:@rules, { "typography" => { "accessibility" => { "normal_text_contrast" => 7.0 } } })
      budget = { "contrast_below_aa" => 0, "contrast_below_aaa" => 38 }
      check.define_singleton_method(:contrast_budget) { budget }
      check.instance_variable_set(:@tokens, {})
      check.instance_variable_set(:@result, Deploy::CheckResult.new)

      check.send(:judge_contrast_budget, 0, 38)

      result = check.instance_variable_get(:@result)
      assert_includes result.warnings, "design_metrics contrast_below_aaa: at its 38 ceiling"
    end
  end

  def test_contrast_ceilings_exist_for_both_bands
    assert_kind_of Integer, budget["contrast_below_aa"]
    assert_kind_of Integer, budget["contrast_below_aaa"]
  end

  # The ceilings existing in the YAML and the check reaching them are two facts,
  # and only the first was asserted. Every budget reader here rescues and runs
  # unbudgeted, so a path that stops resolving costs the ceiling and leaves the
  # check green — which is what a file move did to design_metrics twice, the
  # second time on 2026-09-08 despite a comment in the file warning about the
  # first. A reader that returns nothing is the failure; assert what it returns.
  def test_every_budget_reader_reaches_its_file
    readers = {
      "design_metrics contrast" => Deploy::DesignMetricsCheck.new.send(:contrast_budget),
      "css_constitution rules" => Deploy::CssConstitutionCheck.new.send(:budgets),
      "css_constitution weight" => Deploy::CssConstitutionCheck.new.send(:weight_ceilings),
      "constitutional_scan targets" => Deploy::ConstitutionalScanCheck.new.send(:budget)
    }

    readers.each do |name, values|
      refute_empty values, "#{name}: budget unreadable, so the check runs unbudgeted and still reports ok"
    end
  end

  # The vertical accents live in their own top-level map with no background of
  # their own, so token_pairs -- which pairs inside one dialect -- never saw them.
  #
  # The dialect they are paired against comes from the constant, not from a
  # literal here: it moved from "social" to "brgen_old_dark" at 9cefb0e02
  # ("design_metrics measured contrast on colours nothing paints") and this test
  # kept asserting the old label, so it had been failing on a rename rather than
  # on a measurement.
  def test_vertical_accents_measure_the_foreground_and_fill_that_are_actually_rendered
    pairs = Deploy::DesignMetrics.vertical_accent_pairs(
      design_tokens,
      Deploy::DesignMetricsCheck::RAILS,
    )

    refute_empty pairs
    labels = pairs.map { |pair| pair[:label] }

    assert_includes labels, "vertical_accent_ink/vertical_accents.marketplace_hover"
    assert_includes labels, "vertical_accent_ink/vertical_accents.tv_hover"
  end

  # Not a specific colour: an accent that gets fixed should not fail this. What
  # must hold is that the pairing still surfaces something token_pairs missed,
  # which is the reason it was written. Today the hovers are what it catches.
  #
  # Called the way DesignMetricsCheck calls it. The hover pairs are the accent ink
  # on the hover fill, and the ink is read from the stylesheets under the RAILS
  # root, so without the root there are no hover pairs to find.
  def test_the_vertical_pairing_still_surfaces_a_finding
    pairs = Deploy::DesignMetrics.vertical_accent_pairs(design_tokens, Deploy::DesignMetricsCheck::RAILS)
    below_aa = pairs.select { |pair| pair[:ratio] < 4.5 }

    refute_empty below_aa, "every vertical accent now clears AA - retire this pairing or lower the bar deliberately"
    assert below_aa.all? { |pair| pair[:bg_key].end_with?("_hover") },
           "an accent, not just a hover, is below AA: #{below_aa.map { |pair| pair[:label] }.join(", ")}"
  end

  def test_danger_reads_as_a_foreground_token
    assert_match Deploy::DesignMetrics::FOREGROUND_KEY, "danger"
    assert_match Deploy::DesignMetrics::FOREGROUND_KEY, "dark_danger"
  end

  def test_light_theme_scan_preserves_nested_scope_and_covers_engine_stylesheets
    Dir.mktmpdir("design-metrics") do |root|
      fixtures = {
        "__shared/app/assets/stylesheets/nested.scss" => <<~SCSS,
          :root[data-theme="light"] {
            .first {
              color: var(--text);
            }
            .second {
              color: var(--vertical-marketplace-accent-hover);
            }
          }
          // Historical note: --vertical-marketplace-accent-hover was used outside this block.
        SCSS
        "brgen_sample/app/assets/stylesheets/engine.scss" => <<~SCSS,
          :root[data-theme="light"] {
            .engine-action {
              color: var(--vertical-engine-accent-hover);
            }
          }
        SCSS
        "brgen/app/assets/stylesheets/outside.scss" => <<~SCSS,
          .outside {
            color: var(--vertical-outside-accent-hover);
          }
        SCSS
      }

      fixtures.each do |relative, source|
        path = File.join(root, relative)
        FileUtils.mkdir_p(File.dirname(path))
        File.write(path, source)
      end

      keys = Deploy::DesignMetrics.light_only_vertical_keys(root)

      assert_includes keys, "marketplace_hover",
                      "a nested selector must not end the enclosing light-theme scope"
      assert_includes keys, "engine_hover",
                      "engine stylesheets must be included in the scan"
      refute_includes keys, "outside_hover",
                      "a token also used outside light theme is not light-only"
    end
  end

  def test_a_child_combinator_with_a_nonzero_margin_is_gap_over_margin_debt
    check = spacing_check
    check.send(:scan_spacing, "fixture.scss", <<~CSS)
      .stack > * { margin-bottom: 8px; }
      .stack > * { margin: 0; }
      .stack { margin-bottom: 8px; }
    CSS

    assert_equal [ "fixture.scss:1" ], check.tally.fetch("child_margin")
  end

  def test_card_padding_other_than_24px_is_counted
    check = spacing_check
    check.send(:scan_spacing, "fixture.scss", <<~CSS)
      .card { padding: 1rem; }
      .card { padding: 1.5rem; }
      .card { padding: var(--space-6); }
      .card-grid { padding: 8px; }
    CSS

    assert_equal [ "fixture.scss:1 1rem" ], check.tally.fetch("card_padding")
  end

  def test_a_line_height_literal_is_counted_and_a_leading_token_is_not
    check = spacing_check
    check.instance_variable_set(:@design, {})
    check.send(:count_budget_rules, "fixture.scss", "fixture.scss", <<~CSS)
      .a { line-height: 1.5; }
      .b { line-height: var(--leading-normal); }
      .c { line-height: normal; }
      .d { font-size: 14px; line-height: 20px; }
    CSS

    assert_equal [ "fixture.scss:1 1.5", "fixture.scss:4 20px" ], check.tally.fetch("leading")
  end

  def test_shared_component_partials_preserve_order_and_file_line_budget
    root = File.expand_path("../..", __dir__)
    styles = File.join(root, "RAILS", "__shared", "app", "assets", "stylesheets")
    wrapper = File.read(File.join(styles, "_components.scss"))
    names = %w[forms overlays feedback fields progress_and_uploads content_controls]
    uses = wrapper.scan(/@use "components\/([^"]+)"/).flatten
    ceiling = Shared::FrontendLawSet::TYPOGRAPHY.fetch(:max_css_file_lines)

    assert_equal names, uses, "the wrapper's module order is part of the existing cascade"
    names.each do |name|
      path = File.join(styles, "components", "_#{name}.scss")
      assert File.file?(path), "#{name} component partial is missing"
      assert_operator File.readlines(path).length, :<=, ceiling,
                      "#{path} exceeds the shared CSS file line ceiling"
    end
  end
end
