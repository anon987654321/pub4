# frozen_string_literal: true

require_relative "test_helper"
require_relative "../lib/operator/gate_chain"
require_relative "../lib/operator/readers"

# The four governed trees are one list, MasterPaths::TREES. A second literal in
# lib/ is a list that drifts when a fifth tree arrives.
class TestTreeListSingleSource < Minitest::Test
  LITERAL = /%w\[\s*(MASTER|RAILS|OPENBSD|STUDIO)\s+(MASTER|RAILS|OPENBSD|STUDIO)\s+(MASTER|RAILS|OPENBSD|STUDIO)\s+(MASTER|RAILS|OPENBSD|STUDIO)\s*\]/

  def test_the_list_is_the_four_trees
    assert_equal %w[MASTER RAILS OPENBSD STUDIO], MasterPaths::TREES
    assert_predicate MasterPaths::TREES, :frozen?
  end

  def test_the_named_constants_read_the_one_list
    {
      Master::Convergence => :ROOTS, Master::Core::Constitution => :REPO_TREES,
      Master::Fix::Reachability => :TOP_LEVEL_TREES, Master::Fix::WorktreeSession => :TREES,
      Operator::GateChain => :TREES, Operator::Readers => :TREES, Master::Snapshot => :DEFAULT_TREES
    }.each do |owner, name|
      assert_equal MasterPaths::TREES, owner.const_get(name).to_a, "#{owner}::#{name}"
    end
    assert_same MasterPaths::TREES, Master::Convergence::ROOTS
  end

  def test_no_other_lib_file_spells_the_list
    lib = File.expand_path("../lib", __dir__)
    offenders = Dir.glob(File.join(lib, "**", "*.rb")).select do |path|
      next false if path.end_with?("boot/paths.rb")

      File.foreach(path).any? { |line| line.match?(LITERAL) && !line.lstrip.start_with?("#") }
    end
    assert_empty offenders.map { |path| path.delete_prefix("#{lib}/") }
  end
end
