# frozen_string_literal: true

require_relative "test_helper"
require "review/scan/rule_dsl"

class TestCosmeticRules < Minitest::Test
  def test_ruby_snake_methods_flags_camel_case
    findings = rule("RUBY_SNAKE_METHODS").check("def fetchAlbum\nend\n", path: "lib/foo.rb")
    refute_empty findings
  end

  def test_en_dash_range_flags_hyphen_range_in_prose
    findings = rule("EN_DASH_RANGE").check("Ideal line length is 45-75 characters.\n", path: "README.md")
    refute_empty findings
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
