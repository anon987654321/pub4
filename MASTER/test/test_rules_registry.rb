# frozen_string_literal: true

require_relative "test_helper"

# Was test_split_rules.rb, which asserted the four data/rules/*.yml shards were
# on disk. They were folded into data/rules.yml on 2026-08-12, so that assertion
# now describes the old shape. What it was really protecting — that every scope
# still reaches the scanners through one loader, and that nothing silently
# returns an empty registry — is what these assert instead.
class TestRulesRegistry < Minitest::Test
  SCOPES = %w[codebase file line unit].freeze

  def test_all_scopes_load_from_the_single_rules_file
    rules = Master.load_rules(root: Master::ROOT).fetch("rules", {})

    assert_kind_of Hash, rules
    assert_equal SCOPES.sort, rules.keys.sort
    SCOPES.each do |scope|
      refute_empty Array(rules[scope]), "scope #{scope} loaded no rules"
    end
  end

  def test_registry_is_not_quietly_empty
    total = Master.load_rules(root: Master::ROOT).fetch("rules", {}).values.flatten.size

    assert_operator total, :>=, 200, "expected 200+ rules, got #{total}"
  end

  def test_every_rule_has_an_id
    rules = Master.load_rules(root: Master::ROOT).fetch("rules", {})
    missing = rules.flat_map do |scope, list|
      Array(list).each_with_index.filter_map { |rule, i| "#{scope}[#{i}]" if rule["id"].to_s.strip.empty? }
    end

    assert_empty missing, "rules without an id: #{missing.join(', ')}"
  end

  # The fold put four documents in one file under one key. A duplicate id across
  # what used to be separate files would previously have been two rules in two
  # scopes; it is now a collision worth naming.
  def test_ids_are_unique_within_a_scope
    rules = Master.load_rules(root: Master::ROOT).fetch("rules", {})
    dupes = rules.flat_map do |scope, list|
      ids = Array(list).map { |rule| rule["id"] }
      ids.tally.select { |_, n| n > 1 }.keys.map { |id| "#{scope}:#{id}" }
    end

    assert_empty dupes, "duplicate rule ids: #{dupes.join(', ')}"
  end

  # A foreign root has no rules.yml, and that is an answer rather than a fault —
  # every scanner passes the directory it is scanning.
  def test_foreign_root_returns_empty_without_raising
    Dir.mktmpdir do |dir|
      assert_empty Master.load_rules(root: dir)
    end
  end
end
