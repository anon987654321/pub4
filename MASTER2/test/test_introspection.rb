# frozen_string_literal: true

require_relative "test_helper"

class TestIntrospection < Minitest::Test
  def setup
    # Use the test directory itself as root to keep scans fast and bounded
    @root = File.expand_path("../test", __dir__)
  end

  def test_module_is_defined
    assert defined?(MASTER::Analysis::Introspection)
  end

  def test_summary_returns_string
    result = MASTER::Analysis::Introspection.summary(@root)
    assert_kind_of String, result
    refute_empty result
  end

  def test_summary_matches_lib_test_format
    result = MASTER::Analysis::Introspection.summary(@root)
    assert_match(/\d+ lib/, result)
    assert_match(/\d+ test/, result)
  end

  def test_generate_map_returns_hash_with_required_keys
    map = MASTER::Analysis::Introspection.generate_map(@root)
    assert_kind_of Hash, map
    assert map.key?(:files)
    assert map.key?(:ruby_files)
    assert map.key?(:lib_files)
    assert map.key?(:test_files)
  end

  def test_generate_map_ruby_files_are_all_rb
    map = MASTER::Analysis::Introspection.generate_map(@root)
    map[:ruby_files].each do |f|
      assert f.end_with?(".rb"), "Expected .rb file, got: #{f}"
    end
  end

  def test_generate_map_finds_ruby_files
    map = MASTER::Analysis::Introspection.generate_map(@root)
    refute_empty map[:ruby_files]
  end

  def test_tree_string_returns_string
    result = MASTER::Analysis::Introspection.tree_string(@root)
    assert_kind_of String, result
    refute_empty result
  end

  def test_tree_string_contains_ruby_files
    result = MASTER::Analysis::Introspection.tree_string(@root)
    assert_match(/\.rb/, result)
  end

  def test_tree_string_uses_ascii_connectors
    result = MASTER::Analysis::Introspection.tree_string(@root)
    assert_match(/`-- |\|-- /, result)
  end
end
