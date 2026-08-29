# frozen_string_literal: true

require_relative "test_helper"
require "review/scan/rule_dsl"

class TestCosmeticRules < Minitest::Test
  def test_ruby_snake_methods_flags_camel_case
    refute_empty law_findings("RUBY_SNAKE_METHODS", "def fetchAlbum\nend\n", path: "lib/foo.rb")
  end

  def test_en_dash_range_flags_hyphen_range_in_prose
    findings = rule("EN_DASH_RANGE").check("Ideal line length is 45-75 characters.\n", path: "README.md")
    refute_empty findings
  end

  # A date, a model id and a regex character class each carry a hyphen between
  # digits, and none of them is a range. Unheld, this rule read the repo's own
  # decision log as a typography defect: 200 of 207 findings were dates.
  def test_en_dash_range_ignores_dates_ids_and_char_classes
    [
      "The push landed on 2026-08-10 and reverted on 2026-08-12.\n",
      "model0: claude-opus-4-8\n",
      "MAGIC_NUMBER is /(?:[2-9]|[1-9])/\n",
      "It ran flux-1.1-pro-ultra instead.\n"
    ].each do |line|
      assert_empty rule("EN_DASH_RANGE").check(line, path: "README.md"), line
    end
  end

  def test_tab_character_flags_tabs
    findings = rule("TAB_CHARACTER").check("def foo\n\tbar\nend\n", path: "lib/foo.rb")
    refute_empty findings
  end

  # MEASURE_OPTIMUM lives once, in law/ — its scanner surface is the bridge.
  def test_measure_optimum_flags_wide_px
    findings = Master::Review::Scan::Rules::LawBridgeRule.new
      .check(".prose { max-width: 960px; }\n", path: "app.css")
      .select { |f| f[:rule] == "MEASURE_OPTIMUM" }
    refute_empty findings
  end
end
