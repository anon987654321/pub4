# frozen_string_literal: true

require_relative "test_helper"

# Was test_split_rules.rb, which asserted the four data/rules/*.yml shards were
# on disk; they folded into data/rules.yml on 2026-08-12 and the scope grouping
# that survived the fold went on 2026-09-05. Nothing read it: every consumer
# called flatten_rules, which discarded it immediately, and rules_for_scope had
# no callers at all. What these assert is what the grouping was standing in for
# -- one loader, a registry that is never quietly empty, and ids that collide
# nowhere rather than only within a scope.
class TestRulesRegistry < Minitest::Test
  def rules = Master.load_rules(root: Master::ROOT).fetch("rules", [])

  def test_the_registry_is_one_flat_list
    assert_kind_of Array, rules
    assert(rules.all?(Hash), "every entry is a rule object")
  end

  def test_registry_is_not_quietly_empty
    assert_operator rules.size, :>=, 200, "expected 200+ rules, got #{rules.size}"
  end

  def test_every_rule_has_an_id
    missing = rules.each_with_index.filter_map { |rule, i| "rules[#{i}]" if rule["id"].to_s.strip.empty? }

    assert_empty missing, "rules without an id: #{missing.join(', ')}"
  end

  # Uniqueness is now across the whole catalogue rather than within a scope,
  # which is strictly stronger: two rules sharing an id in different scopes used
  # to pass, and their findings were indistinguishable in any report.
  def test_ids_are_unique
    dupes = rules.map { |rule| rule["id"] }.tally.select { |_, n| n > 1 }.keys

    assert_empty dupes, "duplicate rule ids: #{dupes.join(', ')}"
  end
end
