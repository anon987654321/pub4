# frozen_string_literal: true

require "minitest/autorun"
require "tmpdir"
require_relative "../check.rb"

class TestToolsCheck < Minitest::Test
  CHECK = Deploy::ToolsCheck

  def check = @check ||= CHECK.new

  def test_declared_tree_matches_real_files
    CHECK::TREES.each do |tree|
      matches = check.source_files.select { |path| check.send(:tree_matches?, tree, path) }
      refute_empty matches, "#{tree[:name]} owns no source files"
    end
  end

  def test_every_entry_point_exists_and_is_guarded
    CHECK::TREES.each do |tree|
      next unless tree[:entry]

      path = File.join(CHECK::ROOT, tree[:entry])
      assert File.file?(path)
      assert_match(/__FILE__\s*==\s*(\$PROGRAM_NAME|\$0)/, File.read(path))
    end
  end

  def test_every_source_file_belongs_to_a_declared_tree
    unowned = check.source_files.reject { |path| CHECK::TREES.any? { |tree| check.send(:tree_matches?, tree, path) } }
    assert_empty unowned, "unowned MASTER/tools sources: #{unowned.inspect}"
  end

  def test_real_tools_check_measures_source
    result = check.run
    assert_operator result.checks_ran, :>, 0
    refute result.measured_nothing?, result.nothing_measured_reason.to_s
  end
end
