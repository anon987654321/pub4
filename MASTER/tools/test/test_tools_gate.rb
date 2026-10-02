# frozen_string_literal: true

require "minitest/autorun"
require_relative "../gate.rb"

class TestToolsGate < Minitest::Test
  GATE = Deploy::ToolsGate

  def gate = @gate ||= GATE.new

  def test_declared_tree_matches_real_files
    GATE::TREES.each do |tree|
      matches = Dir[File.join(GATE::ROOT, tree[:glob])].reject { |p| GATE.vendored?(p) }
      refute_empty matches, "#{tree[:name]} matches nothing"
    end
  end

  def test_every_entry_point_exists_and_is_guarded
    GATE::TREES.each do |tree|
      next unless tree[:entry]
      path = File.join(GATE::ROOT, tree[:entry])
      assert File.file?(path)
      assert_match(/__FILE__\s*==\s*(\$PROGRAM_NAME|\$0)/, File.read(path))
    end
  end

  def test_every_source_file_belongs_to_a_declared_tree
    unowned = gate.source_files.reject do |path|
      GATE::TREES.any? do |tree|
        File.fnmatch?(File.join(GATE::ROOT, tree[:glob]), path, File::FNM_PATHNAME)
      end
    end
    assert_empty unowned, "unowned MASTER/tools sources: #{unowned.inspect}"
  end

  def test_real_tools_gate_measures_source
    result = gate.run
    assert_operator result.checks_ran, :>, 0
    refute result.measured_nothing?, result.nothing_measured_reason.to_s
  end
end
