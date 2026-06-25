# frozen_string_literal: true

require_relative "test_helper"

class TestSplitRules < Minitest::Test
  def test_rules_shards_present_and_merge
    root = Master::ROOT
    merged = Master.load_rules(root:)
    rules = merged.fetch("rules", {})
    assert rules.is_a?(Hash)
    total = rules.values.flatten.size
    assert_operator total, :>=, 200, "expected 200+ rules from shards, got #{total}"

    %w[codebase file unit line].each do |scope|
      shard = File.join(root, "data", "rules", "#{scope}.yml")
      assert File.file?(shard), "missing shard #{shard}"
    end
  end
end