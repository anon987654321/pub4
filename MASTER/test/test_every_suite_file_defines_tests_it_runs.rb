# frozen_string_literal: true

require_relative "test_helper"
require "prism"

# The cheap half of test_suite_actually_runs.rb, in the default run.
#
# That audit asks each file, in its own process, how many runs it reports, and
# is opt-in because a process per file is slow. The shape it catches most often
# is visible without running anything: a `def test_` that sits outside any test
# class is defined on Object and never collected, and a file whose tests all sit
# there reports zero runs while the aggregate hides it. Prism reads that shape
# in one pass over the suite.
class TestEverySuiteFileDefinesTestsItRuns < Minitest::Test
  ROOT = File.expand_path("..", __dir__)

  # Counts `def test_*` inside a class whose superclass names a Test, and
  # outside one.
  class TestDefinitions < Prism::Visitor
    attr_reader :collected, :stray

    def initialize
      super
      @superclasses = []
      @collected = 0
      @stray = 0
    end

    def visit_class_node(node)
      @superclasses << node.superclass&.slice.to_s
      super
      @superclasses.pop
    end

    def visit_def_node(node)
      if node.name.start_with?("test_")
        @superclasses.any? { |name| name.include?("Test") } ? @collected += 1 : @stray += 1
      end
      super
    end
  end

  def self.definitions(source)
    visitor = TestDefinitions.new
    Prism.parse(source).value.accept(visitor)
    visitor
  end

  def suite_files
    (Dir.glob(File.join(ROOT, "test", "test_*.rb")) + Dir.glob(File.join(ROOT, "spec", "**", "*_spec.rb")))
      .reject { |path| path.end_with?("test_helper.rb") }
  end

  def test_every_suite_file_collects_at_least_one_test_and_strands_none
    files = suite_files
    assert_operator files.size, :>, 100, "the glob found too few files to be reading the suite"

    silent = files.filter_map do |path|
      found = self.class.definitions(File.read(path))
      "#{path.delete_prefix("#{ROOT}/")} (collected #{found.collected}, stray #{found.stray})" if found.collected.zero? || found.stray.positive?
    end

    assert_empty silent, "these files define tests Minitest will not run"
  end

  def test_the_counter_tells_a_collected_test_from_a_stranded_one
    source = <<~RUBY
      class TestThing < Minitest::Test
        def test_inside = nil
      end
      def test_outside = nil
      class Helper
        def test_not_a_test_class = nil
      end
    RUBY

    found = self.class.definitions(source)

    assert_equal 1, found.collected
    assert_equal 2, found.stray
  end
end
