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

  # soul.yml EXEMPTIONS_EXPIRE, made executable for the one opt-out this lint
  # owns. `chrome_i18n: ok` silences a line; when that line stops matching the
  # rule — the string gets translated, the element is deleted, the markup moves —
  # the marker stays and silences whatever occupies those lines next.
  #
  # Written after deleting FINAL_TODO.md left two MASTER baselines still granting
  # it exemptions for dimensions and a path that no longer existed. Both were
  # caught, by tests that check exactly this. Inline opt-outs are the harder case
  # because they sit next to code that moves under them.
  #
  # 0 today across all 6. This is a ratchet at zero, not a tolerance.
  def test_no_opt_out_has_outlived_what_it_excuses
    rules = [
      Pub4::ChromeI18nLint::EMPTY_TITLE,
      Pub4::ChromeI18nLint::SEARCH_PLACEHOLDER,
      Pub4::ChromeI18nLint::ARIA_LABEL,
    ]

    paths = Pub4::ChromeI18nLint.view_paths
    refute_empty paths, "no views found — the glob stopped matching, which is blindness not cleanliness"

    stale = paths.flat_map do |path|
      lines = File.readlines(path, encoding: "UTF-8")
      lines.each_with_index.filter_map do |line, i|
        next unless line.include?(Pub4::ChromeI18nLint::OPT_OUT)

        # The marker guards its own line and the next two — the same window
        # comment_or_opt_out? uses, read forwards.
        window = lines[i..[i + 2, lines.size - 1].min].join
        next if rules.any? { |re| window.match?(re) }

        "#{Pub4::ChromeI18nLint.rel(path)}:#{i + 1}"
      end
    end

    assert_empty stale.sort,
                 "these `#{Pub4::ChromeI18nLint::OPT_OUT}` markers no longer excuse anything — " \
                 "delete them, or they will silence whatever lands on those lines next"
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
