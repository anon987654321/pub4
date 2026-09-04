# frozen_string_literal: true

require_relative "test_helper"
require "review/scan/rule_dsl"
require "tmpdir"
require "fileutils"

# The gate that asks whether every Rule subclass has a test, which for most of
# its life examined one rule file in sixteen and was wrong about that one. It
# returned early unless the path ended `_rule.rb` — only `law_bridge_rule.rb`
# does, the other fifteen being `*_rules.rb` — and then looked for
# `<base>_test.rb` while this tree names tests `test_<base>.rb`, 283 files to 1.
# Its single output was a false positive about a test that existed.
#
# Both halves are pinned below, because either one regressing restores a gate
# that reports nothing and looks green doing it.
class TestRuleCoverageRule < Minitest::Test
  Rules = Master::Review::Scan::Rules

  ONE_CLASS = <<~RUBY
    class WidgetRule < Rule
      def initialize = @id = "WIDGET"
    end
  RUBY

  TWO_CLASSES = <<~RUBY
    class WidgetRule < Rule
      def initialize = @id = "WIDGET"
    end
    class SprocketRule < Rule
      def initialize = @id = "SPROCKET"
    end
  RUBY

  # The rule keys off a path containing /review/scan/rules/, so the fixture
  # supplies one; only the test directory has to exist on disk.
  def messages(code, test_files: {}, path: "/x/lib/review/scan/rules/widget_rules.rb")
    Dir.mktmpdir do |root|
      FileUtils.mkdir_p(File.join(root, "test"))
      test_files.each { |name, body| File.write(File.join(root, "test", name), body) }
      Rules::RuleCoverageRule.new(root:).check(code, path:).map(&:message)
    end
  end

  # The regression that matters most: a plural filename must be examined. The
  # old rule skipped every one of these, which is fifteen of sixteen real files.
  def test_a_plural_rules_file_is_examined
    found = messages(ONE_CLASS)

    assert_equal ["rule_coverage: no test names WidgetRule"], found
  end

  def test_a_class_named_by_some_test_is_covered
    assert_empty messages(ONE_CLASS, test_files: { "test_anything.rb" => "WidgetRule" })
  end

  # Coverage by rule id, not only by class name, because the tests that exercise
  # these rules in bulk reach them by id through the scanner. Requiring the
  # class name would report those as uncovered.
  def test_a_class_reached_by_its_id_is_covered
    assert_empty messages(ONE_CLASS, test_files: { "test_bulk.rb" => 'rule("WIDGET")' })
  end

  def test_the_id_matches_in_either_case
    assert_empty messages(ONE_CLASS, test_files: { "test_bulk.rb" => "widget" })
  end

  # The name of the test file is not the question. This is the false positive
  # the old glob produced: a real test, named the way this tree names tests,
  # reported as missing.
  def test_the_test_file_name_is_irrelevant
    assert_empty messages(ONE_CLASS, test_files: { "test_widget_rule.rb" => "WidgetRule" })
    assert_empty messages(ONE_CLASS, test_files: { "wildly_unrelated.rb" => "WidgetRule" })
  end

  def test_every_uncovered_class_in_a_file_is_reported
    found = messages(TWO_CLASSES)

    assert_equal 2, found.size
    assert_includes found.join, "WidgetRule"
    assert_includes found.join, "SprocketRule"
  end

  def test_a_covered_class_beside_an_uncovered_one_is_not_reported
    found = messages(TWO_CLASSES, test_files: { "test_partial.rb" => "SprocketRule" })

    assert_equal ["rule_coverage: no test names WidgetRule"], found
  end

  def test_a_file_outside_the_rules_directory_is_skipped
    assert_empty messages(ONE_CLASS, path: "/x/lib/voice/widget_rules.rb")
  end

  def test_a_non_ruby_file_is_skipped
    assert_empty messages(ONE_CLASS, path: "/x/lib/review/scan/rules/widget_rules.yml")
  end

  # Only Rule subclasses. RuleDSL declares dozens of rules inline and the
  # description is about subclasses; counting both would demand a test per
  # declaration and bury the real gap.
  def test_a_plain_class_is_not_a_rule_subclass
    assert_empty messages("class WidgetRule < Something\nend\n")
  end

  def test_it_registers_under_the_id_the_scanner_routes_on
    Dir.mktmpdir { |root| assert_equal "rule_coverage", Rules::RuleCoverageRule.new(root:).id.to_s }
  end
end
