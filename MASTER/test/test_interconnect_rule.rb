# frozen_string_literal: true

require_relative "test_helper"
require "review/scan/rule_dsl"
require "tmpdir"
require "fileutils"

# Reads what a file claims to load from data/ and what it then digs out of it,
# and reports a key the YAML does not have. It is the check against the defect
# this repository calls its dominant one from the other side: not a declaration
# with no reader, but a reader with no declaration.
#
# The load-bearing case is the last one. An unparseable data file must surface
# as a finding rather than being skipped, because a scanner that quietly drops
# a broken constitution validates the tree against a partial one and calls it a
# pass — which is the shape this repo has been bitten by repeatedly.
class TestInterconnectRule < Minitest::Test
  def in_tree(files)
    Dir.mktmpdir do |root|
      FileUtils.mkdir_p(File.join(root, "data"))
      files.each { |name, body| File.write(File.join(root, "data", name), body) }
      yield Master::Review::Scan::Rules::InterconnectRule.new(root:), root
    end
  end

  def flags(rule, code, path: "/x/lib/thing.rb")
    rule.check(code, path:).map(&:message)
  end

  def test_a_key_the_yaml_does_not_have_is_reported
    in_tree("limits.yml" => { "limits" => { "max" => 3 } }.to_yaml) do |rule, _root|
      found = flags(rule, <<~RUBY)
        data = Master.load_yaml("limits.yml")
        data.dig("limits", "minimum")
      RUBY

      assert_equal 1, found.size
      assert_includes found.first, "phantom key"
      assert_includes found.first, "minimum"
    end
  end

  def test_a_key_the_yaml_has_is_silent
    in_tree("limits.yml" => { "limits" => { "max" => 3 } }.to_yaml) do |rule, _root|
      assert_empty flags(rule, <<~RUBY)
        data = Master.load_yaml("limits.yml")
        data.dig("limits", "max")
      RUBY
    end
  end

  # No load call means no claim about a data file, so there is nothing to check
  # against and a dig here is about some other hash entirely.
  def test_a_dig_with_no_loaded_yaml_is_not_its_business
    in_tree("limits.yml" => { "limits" => { "max" => 3 } }.to_yaml) do |rule, _root|
      assert_empty flags(rule, %(payload.dig("limits", "minimum")\n))
    end
  end

  # Only lib/. The rule reads code that consumes the constitution, and a test
  # fixture naming a missing key on purpose is not a defect.
  def test_it_reads_only_library_ruby
    in_tree("limits.yml" => { "limits" => { "max" => 3 } }.to_yaml) do |rule, _root|
      code = %(Master.load_yaml("limits.yml").dig("limits", "minimum")\n)

      assert_empty flags(rule, code, path: "/x/test/test_thing.rb")
      assert_empty flags(rule, code, path: "/x/lib/thing.txt")
    end
  end

  # The one that must never degrade to silence. A data file that will not parse
  # is a broken constitution, and skipping it means scanning against a partial
  # one and reporting a pass.
  def test_an_unparseable_data_file_is_reported_rather_than_skipped
    in_tree("limits.yml" => "limits:\n  max: [unclosed\n") do |rule, _root|
      found = flags(rule, %(Master.load_yaml("limits.yml").dig("limits", "max")\n))

      refute_empty found, "an unreadable data file must not read as a clean scan"
      assert_includes found.first, "failed to parse"
      assert_includes found.first, "limits.yml"
    end
  end

  # A named file that is not there is not a parse failure and not a phantom
  # key — nothing can be said about it, so the rule says nothing.
  def test_a_missing_data_file_is_passed_over
    in_tree({}) do |rule, _root|
      assert_empty flags(rule, %(Master.load_yaml("absent.yml").dig("a", "b")\n))
    end
  end
end
