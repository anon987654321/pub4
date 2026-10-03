# frozen_string_literal: true

require_relative "test_helper"
require "review/scan/rule_dsl"
require "tmpdir"
require "fileutils"

# The escape hatch for declaring a lexical rule in data/rules.yml without
# writing a Ruby class for it. **It compiles nothing today**: no rule in the
# corpus carries `detect_lexical`, so the bridge holds zero entries and cannot
# fire on anything.
#
# That is why this test is built the way it is. Pointing it at the real corpus
# would assert a path production never takes, and a test that passes because
# there is nothing to do is the shape this repo keeps finding and deleting. So
# the corpus is supplied: the mechanism is proved against a rules file written
# for the purpose, and the emptiness of the live one is asserted separately, as
# a fact with a date on it rather than as coverage.
class TestYamlDeclarativeRule < Minitest::Test
  Rules = Master::Review::Scan::Rules

  def in_corpus(rules)
    Dir.mktmpdir do |root|
      FileUtils.mkdir_p(File.join(root, "data"))
      File.write(File.join(root, "data", "rules.yml"), { "rules" => { "line" => rules } }.to_yaml)
      yield Rules::YamlDeclarativeRule.new(root:), root
    end
  end

  def lexical(id:, pattern:, **extra)
    [{ "id" => id, "name" => "declared in yaml", "severity" => "warning",
       "detect_lexical" => pattern, "fix" => "stop it" }.merge(extra)]
  end

  def test_a_declared_lexical_rule_compiles_and_fires
    in_corpus(lexical(id: "NO_FROBNICATE", pattern: "frobnicate")) do |rule, root|
      found = rule.check("value = frobnicate(x)\n", path: File.join(root, "lib/thing.rb"))

      assert_equal 1, found.size
      assert_equal "no_frobnicate", found.first.rule.to_s
      assert_equal 1, found.first.line
    end
  end

  def test_source_that_does_not_match_is_silent
    in_corpus(lexical(id: "NO_FROBNICATE", pattern: "frobnicate")) do |rule, root|
      assert_empty rule.check("value = ordinary(x)\n", path: File.join(root, "lib/thing.rb"))
    end
  end

  def test_the_declared_severity_reaches_the_finding
    in_corpus(lexical(id: "NO_FROBNICATE", pattern: "frobnicate", "severity" => "error")) do |rule, root|
      found = rule.check("frobnicate\n", path: File.join(root, "lib/thing.rb"))

      assert_equal :error, found.first.severity
    end
  end

  # An uncompilable pattern is inert law — listed, counted, never run — and the
  # bridge drops it rather than taking the whole scan down with it. The rest of
  # the corpus has to survive the bad neighbour.
  def test_an_uncompilable_pattern_is_dropped_without_losing_the_others
    rules = lexical(id: "BROKEN", pattern: "([unclosed") + lexical(id: "FINE", pattern: "frobnicate")
    in_corpus(rules) do |rule, root|
      found = rule.check("frobnicate\n", path: File.join(root, "lib/thing.rb"))

      assert_equal 1, found.size
      assert_equal "fine", found.first.rule.to_s
    end
  end

  # A rule with no lexical pattern belongs to a Ruby class or to law/, and the
  # bridge exists only for the ones nothing else covers.
  def test_a_rule_without_a_lexical_pattern_is_not_bridged
    rules = [{ "id" => "SEMANTIC_ONLY", "name" => "x", "severity" => "warning",
               "detect_semantic" => "Is this bad?" }]
    in_corpus(rules) do |rule, root|
      assert_empty rule.check("anything at all\n", path: File.join(root, "lib/thing.rb"))
    end
  end

  # Dated on purpose. The bridge is empty, and the point of asserting it is that
  # the day somebody adds a `detect_lexical` back, this test fails and asks
  # whether the bridge is still wanted — rather than the rule quietly staying a
  # path nothing takes. See TODO.md, "The YAML lexical bridge compiles nothing".
  def test_the_live_corpus_still_declares_no_lexical_rules
    live = Master.flatten_rules(Master.load_rules(root: Master::ROOT).fetch("rules", {}))

    assert_equal 0, live.count { |r| r["detect_lexical"] },
                 "a lexical rule is declared again — the bridge is live, and TODO.md's record of it is stale"
  end
end
