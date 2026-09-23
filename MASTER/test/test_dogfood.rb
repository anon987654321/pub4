# frozen_string_literal: true

require "minitest/autorun"

ROOT = File.expand_path("..", __dir__)
require File.join(ROOT, "law", "law")
# The one loader for constitutional YAML — see the read below and
# test_yaml_registries, which asserts nothing reads those files any other way.
require File.join(ROOT, "lib", "master")

Law.load_all

class DogfoodSpec < Minitest::Test
  # Every law with a detector flags its bad fixture and spares its good one.
  # Failure here is the archaeological audit: a capability went missing, or a
  # detector regressed.
  #
  # A practice rule has no detector — no regex can read "one SSH session" off a
  # file — so its fixtures are illustrative and this proof does not apply. What
  # still applies is that it HAS them: Builder refuses a rule without a bad and a
  # good whatever its kind, because a rule carrying no example of its own subject
  # is the unfalsifiable shape this file exists to reject.
  Law.rules.each do |id, rule|
    if rule.scannable?
      define_method("test_law_#{id}_proves_itself") do
        refute_empty rule.scan(rule.bad),  "#{id}: bad fixture not flagged"
        assert_empty rule.scan(rule.good), "#{id}: good fixture flagged (false positive)"
      end
    else
      define_method("test_rule_#{id}_carries_both_examples") do
        refute_empty rule.bad.to_s.strip,  "#{id}: no example of breaking it"
        refute_empty rule.good.to_s.strip, "#{id}: no example of following it"
        refute_equal rule.bad.to_s.strip, rule.good.to_s.strip, "#{id}: the two examples are the same"
      end
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
    # Master.load_yaml, not YAML directly: test_yaml_registries asserts that
    # every runtime read of a constitutional file goes through the one loader,
    # so a second reader here is a second implementation of what rules.yml means.
    walk.call(Master.load_yaml(Master::RULES_PATH))
    assert_empty left, "detect_lexical belongs in law/ now: #{left.join(', ')}"
  end
end
