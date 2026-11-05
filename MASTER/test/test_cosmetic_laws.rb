# frozen_string_literal: true

require_relative "test_helper"
require "review/scan/law_tree"

class TestCosmeticRules < Minitest::Test
  def test_ruby_snake_methods_flags_camel_case
    refute_empty law_findings("RUBY_SNAKE_METHODS", "def fetchAlbum\nend\n", path: "lib/foo.rb")
  end

  # A tab separates fields in a .tsv and in the two base-system config files
  # kept as OpenBSD ships them; in a script it is still indentation.
  def test_tab_character_spares_tab_delimited_data
    row = "name\tdomain\n"
    assert_empty rule("TAB_CHARACTER").check(row, path: "STUDIO/dilla/demo_manifest.tsv")
    assert_empty rule("TAB_CHARACTER").check(row, path: "OPENBSD/etc/login.conf")
    assert_empty rule("TAB_CHARACTER").check(row, path: "OPENBSD/etc/newsyslog.conf")
    refute_empty rule("TAB_CHARACTER").check("f() {\n\tprint hi\n}\n", path: "OPENBSD/usr/local/bin/uptime-check.sh")
  end

  # The operator's rule: punctuation is ASCII in every file, copy included.
  # The banned marks are escapes so this test file obeys the Law it proves.
  def test_ascii_punctuation_flags_each_banned_mark
    Master::Content::AsciiPunctuation::REPLACEMENTS.each_key do |mark|
      refute_empty rule("ASCII_PUNCTUATION").check("Open 10#{mark}16\n", path: "README.md"), mark.inspect
    end
  end

  def test_ascii_punctuation_allows_letters_and_ascii
    copy = "Åpent 10-16 - blåbær... \"ja\" -> ok\n"
    assert_empty rule("ASCII_PUNCTUATION").check(copy, path: "config/locales/nb.yml")
  end

  def test_ascii_punctuation_leaves_soul_to_the_operator
    assert_empty rule("ASCII_PUNCTUATION").check("A \u2014 B\n", path: "MASTER/data/soul.yml")
  end

  def test_ascii_punctuation_rewrites_separators_by_position
    rewrite = ->(text) { Master::Content::AsciiPunctuation.rewrite(text) }

    assert_equal "a - b", rewrite.call("a\u2014b")
    assert_equal "a - b", rewrite.call("a \u00B7 b")
    assert_equal "  - item\n", rewrite.call("  \u2022 item\n")
    assert_equal "end -\n", rewrite.call("end \u2014\n")
    marks = "10\u201316 \u2026 \u201Cx\u201D it\u2019s \u2192 2\u00D7 \u2265"
    assert_equal "10-16 ... \"x\" it's -> 2x >=", rewrite.call(marks)
  end

  # Under ASCII_PUNCTUATION a locale's ellipsis is three dots, and copy that
  # trails off is not a placeholder; the same dots ending Ruby still are.
  def test_completion_theater_reads_a_locale_ellipsis_as_copy
    locale = "en:\n  loading: Loading the room...\n"
    assert_empty rule("COMPLETION_THEATER").check(locale, path: "RAILS/brgen/config/locales/en.yml")
    refute_empty rule("COMPLETION_THEATER").check("def run\n  ...\n", path: "MASTER/lib/run.rb")
  end

  def test_tab_character_flags_tabs
    findings = rule("TAB_CHARACTER").check("def foo\n\tbar\nend\n", path: "lib/foo.rb")
    refute_empty findings
  end

  def test_measure_optimum_flags_wide_px
    refute_empty law_findings("MEASURE_OPTIMUM", ".prose { max-width: 960px; }\n", path: "app.css")
  end
end
