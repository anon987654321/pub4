# frozen_string_literal: true

require_relative "test_helper"
require "review/scan/law_tree"
require "tmpdir"
require "fileutils"

# The check asks whether each detector class is referenced by a test,
# whatever the detector file or the test file is called.
#
# Both halves are pinned below, because either one regressing restores a check
# that reports nothing and looks green doing it.
class TestLawCoverageLaw < Minitest::Test
  Laws = Master::Review::Scan::Laws

  ONE_CLASS = <<~RUBY
    class WidgetLaw < Detector
    end

    ::Law.define(:WIDGET) do
      detector WidgetLaw
    end
  RUBY

  TWO_CLASSES = <<~RUBY
    class WidgetLaw < Detector
    end

    ::Law.define(:WIDGET) do
      detector WidgetLaw
    end

    class SprocketLaw < Detector
    end

    ::Law.define(:SPROCKET) do
      detector SprocketLaw
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

  # A plural filename must be examined: most real detector files are plural.
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

  # A detector class gets its id from the ::Law.define that names it, so that is
  # where the id is read. Both directions: the shape the tree writes must be found,
  # and an `@id = "..."` assignment, which the tree does not use, must not.
  def test_the_id_is_read_from_the_declaration_the_tree_writes
    assert_empty messages(ONE_CLASS, test_files: { "test_bulk.rb" => 'rule("WIDGET")' })
    refute_empty messages(<<~RUBY, test_files: { "test_bulk.rb" => 'rule("WIDGET")' })
      class WidgetLaw < Detector
        def initialize = @id = "WIDGET"
      end
    RUBY
  end

  # A Law covered from spec/ is covered; reading only test/ would invent a gap.
  def test_a_class_named_from_spec_is_covered
    assert_empty messages(ONE_CLASS, test_files: { "widget_rule_spec.rb" => "WidgetLaw" }, dir: "spec")
  end

  # The name of the test file is not the question: a real test, named any way,
  # is coverage.
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

  # Only detector classes. A `check` Law is a block inside ::Law.define and the
  # description is about classes; counting both would demand a test per
  # declaration and bury the real gap.
  def test_a_plain_class_is_not_a_rule_subclass
    assert_empty messages("class WidgetLaw < Something\nend\n")
  end

  def test_it_registers_under_the_id_the_scanner_routes_on
    Dir.mktmpdir { |root| assert_equal "law_coverage", Laws::LawCoverageLaw.new(root:).id.to_s }
  end
end
