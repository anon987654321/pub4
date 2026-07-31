# frozen_string_literal: true

require "minitest/autorun"
require_relative "../shared/lib/pub4/chrome_i18n_lint"

class ChromeI18nLintTest < Minitest::Test
  def test_baseline_zero_on_tree
    findings = Pub4::ChromeI18nLint.scan
    assert_equal 0, findings.size,
      "chrome_i18n_lint baseline is 0; new hardcoded EN chrome:\n" \
      "#{findings.first(10).map { |f| "  #{f.file}:#{f.line} [#{f.kind}]" }.join("\n")}"
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
end
