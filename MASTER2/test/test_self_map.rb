# frozen_string_literal: true

require "minitest/autorun"
require_relative "../lib/master"

class TestSelfMap < Minitest::Test
  def test_self_aware
    assert MASTER::SelfMap.self_aware?, "MASTER should recognize its own files"
  end

  def test_tree_returns_entries
    entries = MASTER::SelfMap.tree
    assert entries.length > 0, "Tree should have entries"
    assert entries.any? { |e| e[:path] == "lib/master.rb" }
  end

  def test_tree_excludes_dotfiles
    entries = MASTER::SelfMap.tree
    refute entries.any? { |e| e[:path].start_with?(".") }, "Should exclude dotfiles"
  end

  def test_ruby_files
    rb = MASTER::SelfMap.ruby_files
    assert rb.all? { |f| f[:ext] == ".rb" }
    assert rb.length > 0
  end

  def test_yaml_files
    yml = MASTER::SelfMap.yaml_files
    assert yml.all? { |f| [".yml", ".yaml"].include?(f[:ext]) }
    assert yml.length > 0
  end

  def test_summary
    s = MASTER::SelfMap.summary
    assert s[:root]
    assert s[:files] > 0
    assert s[:directories] > 0
    assert s[:by_extension].key?(".rb")
  end

  def test_target_directory
    result = MASTER::SelfMap.target("lib")
    assert result.ok?
    groups = result.value
    assert groups[:ruby].length > 0
  end

  def test_target_missing_directory
    result = MASTER::SelfMap.target("nonexistent_dir_xyz")
    assert result.err?
  end
end
