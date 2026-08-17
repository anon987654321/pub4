# frozen_string_literal: true

require "minitest/autorun"

ROOT = File.expand_path("..", __dir__)
require File.join(ROOT, "law", "law")

Law.load_all

class DogfoodSpec < Minitest::Test
  # Every law flags its bad fixture and spares its good one. Failure here is
  # the archaeological audit: a capability went missing, or a detector regressed.
  Law.rules.each do |id, rule|
    define_method("test_law_#{id}_proves_itself") do
      refute_empty rule.scan(rule.bad),  "#{id}: bad fixture not flagged"
      assert_empty rule.scan(rule.good), "#{id}: good fixture flagged (false positive)"
    end
  end

  # Self-application. Law files are Ruby; every ruby-scoped law runs over
  # law/ and must find nothing (declarations and fixtures excepted — Law.conduct).
  def test_law_applies_to_itself
    findings = Dir[File.join(ROOT, "law", "*.rb")].flat_map { |f| Law.scan(f, language: :ruby) }
    assert_empty findings.map { |f| "#{f.id} #{File.basename(f.file)}:#{f.line}" }.join("\n")
  end

  def test_no_law_without_all_three_parts
    err = assert_raises(ArgumentError) { Law.define(:INCOMPLETE) { detect { true } } }
    assert_match(/missing bad, good/, err.message)
  end

  def test_every_lexical_rule_in_rules_yml_has_moved_here
    require "yaml"
    left = []
    walk = lambda do |o|
      case o
      when Hash
        left << o["id"] if o["id"] && o["detect_lexical"]
        o.each_value { |v| walk.call(v) }
      when Array then o.each { |v| walk.call(v) }
      end
    end
    walk.call(YAML.safe_load_file(File.join(ROOT, "data", "rules.yml"), aliases: true))
    assert_empty left, "detect_lexical belongs in law/ now: #{left.join(', ')}"
  end
end
