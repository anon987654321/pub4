# frozen_string_literal: true

require "minitest/autorun"
require_relative "../../MASTER/tools/design/scss_rules"

# The rule reader every stylesheet check leans on once an app has one
# stylesheet. A check scoped by selector is only as honest as the braces it
# counts, so the shapes that break a naive count are pinned here: a comment that
# quotes a rule, a brace inside a string or a url(), and Sass interpolation.
class ScssRulesTest < Minitest::Test
  R = Operator::ScssRules

  SOURCE = <<~'SCSS'
    #navBar {
      box-shadow: 0 1px red;
      .section { margin: 0 }
    }
    @media (min-width: 1px) {
      #navBar .x { color: red; }
      .keep { color: blue }
    }
    /* .ghost { color: red } */ .c { content: "}"; background: url(//x.png); }
    body.vertical-#{$v} { --accent: #{list.nth($c, 1)}; }
    // .quoted { }
    .d, :is(.e, .f) { a: b }
  SCSS

  def selectors = R.rules(SOURCE).map(&:selector)

  def test_comments_strings_urls_and_interpolation_are_not_blocks
    assert_equal ["#navBar", ".section", "@media (min-width: 1px)", "#navBar .x", ".keep", ".c",
                  "body.vertical-\#{$v}", ".d, :is(.e, .f)"], selectors
  end

  def test_a_rule_holds_its_own_declarations_and_not_its_childrens
    nav = R.rules(SOURCE).find { |rule| rule.selector == "#navBar" }

    assert_equal "box-shadow: 0 1px red;", nav.body
    assert_equal [1, 4], [nav.line, nav.end_line]
  end

  def test_nested_selectors_resolve_against_their_parents
    section = R.rules(SOURCE).find { |rule| rule.selector == ".section" }

    assert_equal ["#navBar .section"], section.full_selectors
    assert_equal [".d", ":is(.e, .f)"], R.rules(SOURCE).last.selectors
  end

  def test_matching_reads_selectors_inside_at_rules
    assert_equal ["#navBar", ".section", "#navBar .x"], R.matching(SOURCE, /#navBar/).map(&:selector)
  end

  def test_without_blanks_only_rules_whose_selectors_all_match_and_keeps_lines
    blanked = R.without(SOURCE, /#navBar/)

    assert_equal SOURCE.count("\n"), blanked.count("\n")
    refute_includes blanked, "box-shadow"
    assert_includes blanked, ".keep { color: blue }"
    assert_includes blanked, "@media (min-width: 1px) {"
  end

  def test_partition_hands_matching_runs_back_byte_for_byte
    runs = R.partition(SOURCE, /#navBar/)

    assert_equal SOURCE, runs.map(&:first).join
    assert_equal 2, runs.count(&:last)
  end
end
