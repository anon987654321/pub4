# frozen_string_literal: true

require "minitest/autorun"
require_relative "../shared/lib/pub4/chrome_i18n_lint"

class ChromeI18nLintTest < Minitest::Test
  # Was assert_equal 0, findings.size. The lint now measures three kinds with
  # different baselines: empty titles and search placeholders are solved and stay at
  # 0, hardcoded aria-labels are a measured 172 that may only shrink. One flat number
  # would have forced either 172 permanent failures or no aria rule at all.
  def test_no_kind_exceeds_its_baseline
    findings = Pub4::ChromeI18nLint.scan
    exceeded = Pub4::ChromeI18nLint.over_baseline(findings)

    assert_empty exceeded,
                 "#{exceeded.join("; ")}\n" \
                 "#{findings.first(10).map { |f| "  #{f.file}:#{f.line} [#{f.kind}]" }.join("\n")}"
  end

  # A baseline that has been beaten and never lowered is a baseline nobody trusts.
  def test_baselines_are_not_stale
    counts = Pub4::ChromeI18nLint.counts

    Pub4::ChromeI18nLint::BASELINES.each do |kind, baseline|
      assert_equal baseline, counts.fetch(kind),
                   "#{kind} is at #{counts.fetch(kind)} against a baseline of #{baseline} — " \
                   "lower the baseline in chrome_i18n_lint.rb"
    end
  end

  def test_detects_hardcoded_empty_title
    sample = <<~ERB
      <%= render "shared/empty_state",
            title: "No widgets yet",
            body: "Add one.",
            action: { label: "Add", path: "/" } %>
    ERB
    assert_match(Pub4::ChromeI18nLint::EMPTY_TITLE, sample)
  end

  def test_ignores_t_wrapped_title
    sample = 'title: t("empty.no_widgets")'
    refute_match(Pub4::ChromeI18nLint::EMPTY_TITLE, sample)
  end

  # RAILS/gates/data/GATE_ADEQUACY.md gap 2: a screen-reader user on :nb hears
  # English for every one of these, and nothing counted them.
  def test_detects_hardcoded_aria_labels_in_both_spellings
    [
      %(<section aria-label="Declutter summary">),
      %(<%= link_to "#", aria: { label: "Item actions" } %>),
      %(<div aria-roledescription="carousel">),
    ].each do |sample|
      assert_match(Pub4::ChromeI18nLint::ARIA_LABEL, sample, "should flag #{sample}")
    end
  end

  def test_ignores_translated_or_interpolated_aria_labels
    [
      %(<section aria-label="<%= t("a11y.declutter_summary") %>">),
      %(<div aria-label="<%= @item.name %>">),
    ].each do |sample|
      refute_match(Pub4::ChromeI18nLint::ARIA_LABEL, sample, "should not flag #{sample}")
    end
  end

  def test_a_single_character_label_is_not_worth_translating
    refute_match(Pub4::ChromeI18nLint::ARIA_LABEL, %(<button aria-label="×">))
  end
end
