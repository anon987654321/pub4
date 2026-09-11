# frozen_string_literal: true

require_relative "test_helper"

# Which autofixes may run unattended, and which wait for a person.
#
# Four rules declare a transform. Three add — a lang attribute, a loading
# attribute, a trailing comma — and a wrong one is visible in the diff it makes.
# remove_immediate_dead_code takes code out, and a wrong deletion is invisible to
# anyone who does not already know what stood there.
#
# The gate this replaces could never refuse anything. Its thresholds were keyed
# null_usage, abbreviation and nesting_depth, which name no rule in the catalogue
# and no transform in the tree, so the lookup missed every time and the method
# answered true for every rule on every run — under a backlog entry recording
# that an unattended autofix pass corrupts code.
class TestAutofixSafetyTier < Minitest::Test
  def setup
    @scanner = Master::Review::Scan::Scanner.new
  end

  def test_a_deleting_transform_waits_for_a_person
    refute allowed?("DEAD_CODE"), "remove_immediate_dead_code ran without being asked"
    assert allowed?("DEAD_CODE", deletions: true), "a person asking must still be able to fix it"
  end

  def test_an_adding_transform_runs_unattended
    %w[HTML_LANG LAZY_IMAGES TRAILING_COMMAS].each do |rule|
      assert allowed?(rule), "#{rule} adds and is visible in its own diff"
    end
  end

  # Confidence answers whether the rule found the thing, never whether fixing it
  # is safe, and Fix::RuleLoop reads an absent score as 1.0 — so a threshold
  # waves through exactly the deterministic findings nobody scored. The tier has
  # to read the transform.
  def test_perfect_confidence_does_not_buy_a_deletion
    refute allowed?("DEAD_CODE", confidence: 1.0)
  end

  def test_a_rule_with_no_transform_is_not_treated_as_deleting
    assert allowed?("GUARD_CLAUSE")
  end

  private

  def allowed?(rule, confidence: 1.0, deletions: false)
    @scanner.send(:should_autofix?, rule, confidence, allow_deletions: deletions)
  end
end
