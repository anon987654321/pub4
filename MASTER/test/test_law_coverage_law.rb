# frozen_string_literal: true

require_relative "test_helper"
require "review/scan/law_dsl"
require "tmpdir"
require "fileutils"

# The check asks whether each scanner Law subclass is referenced by a test.
# Its former filename heuristics skipped most detector files and used a test
# naming convention this tree does not follow, so it falsely reported existing tests.
#
# Both halves are pinned below, because either one regressing restores a check
# that reports nothing and looks green doing it.
class TestLawCoverageLaw < Minitest::Test
  Laws = Master::Review::Scan::Laws

  ONE_CLASS = <<~RUBY
    class WidgetLaw < Law
      declare id: "WIDGET"
    end
  RUBY

  TWO_CLASSES = <<~RUBY
    class WidgetLaw < Law
      declare id: "WIDGET"
    end
    class SprocketLaw < Law
      declare id: "SPROCKET"
    end
  RUBY

  # The rule keys off a path under /law/detectors/, so the fixture
  # supplies one; only the source directory has to exist on disk.
  def messages(code, test_files: {}, dir: "test", path: "/x/law/detectors/widget_rules.rb")
    Dir.mktmpdir do |root|
      FileUtils.mkdir_p(File.join(root, dir))
      test_files.each { |name, body| File.write(File.join(root, dir, name), body) }
      Laws::LawCoverageLaw.new(root:).check(code, path:).map(&:message)
    end
  end

  # The regression that matters most: a plural filename must be examined. The
  # old rule skipped every one of these, which is fifteen of sixteen real files.
  def test_a_plural_rules_file_is_examined
    found = messages(ONE_CLASS)

    assert_equal ["law_coverage: no test names WidgetLaw"], found
  end

  def test_a_class_named_by_some_test_is_covered
    assert_empty messages(ONE_CLASS, test_files: { "test_anything.rb" => "WidgetLaw" })
  end

  # Coverage by rule id, not only by class name, because the tests that exercise
  # these rules in bulk reach them by id through the scanner. Requiring the
  # class name would report those as uncovered.
  def test_a_class_reached_by_its_id_is_covered
    assert_empty messages(ONE_CLASS, test_files: { "test_bulk.rb" => 'rule("WIDGET")' })
  end

  def test_the_id_matches_in_either_case
    assert_empty messages(ONE_CLASS, test_files: { "test_bulk.rb" => "rule(:widget)" })
  end

  # A bare word is not a citation of an id. `explicit` and `reek` are ordinary
  # English, and reading them out of a comment would report as covered every rule
  # whose id happens to be a word somebody used — coverage a run did not earn.
  def test_a_bare_word_is_not_coverage
    refute_empty messages(ONE_CLASS, test_files: { "test_bulk.rb" => "# widget behaviour" })
  end

  # The id needle read `@id = "..."` and no Rule subclass in this tree has ever
  # written that; every one declares itself with `declare id:`. So the needle
  # matched nothing, only the class-name half did any work, and the fixtures here
  # kept it green by writing a shape the tree does not use. Both directions: the
  # shape the tree writes must be found, and the shape it abandoned must not.
  def test_the_id_is_read_from_the_declaration_the_tree_writes
    assert_empty messages(ONE_CLASS, test_files: { "test_bulk.rb" => 'rule("WIDGET")' })
    refute_empty messages(<<~RUBY, test_files: { "test_bulk.rb" => 'rule("WIDGET")' })
      class WidgetLaw < Law
        def initialize = @id = "WIDGET"
      end
    RUBY
  end

  # LearnedSmellsLaw's only test is spec/learned_smells_rule_spec.rb, and a rule
  # covered from spec/ read as uncovered — this rule inventing a gap of its own.
  def test_a_class_named_from_spec_is_covered
    assert_empty messages(ONE_CLASS, test_files: { "widget_rule_spec.rb" => "WidgetLaw" }, dir: "spec")
  end

  # The name of the test file is not the question. This is the false positive
  # the old glob produced: a real test, named the way this tree names tests,
  # reported as missing.
  def test_the_test_file_name_is_irrelevant
    assert_empty messages(ONE_CLASS, test_files: { "test_widget_rule.rb" => "WidgetLaw" })
    assert_empty messages(ONE_CLASS, test_files: { "wildly_unrelated.rb" => "WidgetLaw" })
  end

  def test_every_uncovered_class_in_a_file_is_reported
    found = messages(TWO_CLASSES)

    assert_equal 2, found.size
    assert_includes found.join, "WidgetLaw"
    assert_includes found.join, "SprocketLaw"
  end

  def test_a_covered_class_beside_an_uncovered_one_is_not_reported
    found = messages(TWO_CLASSES, test_files: { "test_partial.rb" => "SprocketLaw" })

    assert_equal ["law_coverage: no test names WidgetLaw"], found
  end

  def test_a_file_outside_the_rules_directory_is_skipped
    assert_empty messages(ONE_CLASS, path: "/x/lib/voice/widget_rules.rb")
  end

  def test_a_non_ruby_file_is_skipped
    assert_empty messages(ONE_CLASS, path: "/x/law/detectors/widget_rules.yml")
  end

  # Only Rule subclasses. LawDSL declares dozens of rules inline and the
  # description is about subclasses; counting both would demand a test per
  # declaration and bury the real gap.
  def test_a_plain_class_is_not_a_rule_subclass
    assert_empty messages("class WidgetLaw < Something\nend\n")
  end

  def test_it_registers_under_the_id_the_scanner_routes_on
    Dir.mktmpdir { |root| assert_equal "law_coverage", Laws::LawCoverageLaw.new(root:).id.to_s }
  end
end
