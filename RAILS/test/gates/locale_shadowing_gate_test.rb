# frozen_string_literal: true

require "minitest/autorun"
require "tmpdir"
require_relative "gate_fixture"
require_relative "../../gates/lib/source/locale_shadowing"

# An app's own translation, dead because the engine's copy loads after it.
#
# shared/config/locales sits in I18n.load_path twice and the second entry lands
# after every app, so when both define a key the shared value renders and the
# app's is unreachable. Nothing in Rails says which one won.
#
# The second half is worse and invisible to the first: a key with no value
# parses as nil, and nil REPLACES a hash in I18n's deep merge, so one bare
# `nav:` in shared wipes every navigation label in all three apps. A shadowing
# check compares values that disagree, and a key resolving to nothing disagrees
# with nobody.
#
# The gate reads the tree and its budget file from constants fixed at load time,
# so the fixture is installed by rewriting RAILS_ROOT, APPS and BUDGET. The app
# is named brgen because the orphan half walks a hardcoded tree list.
class LocaleShadowingGateTest < Minitest::Test
  include GateFixture

  GATE = Deploy::LocaleShadowingGate

  def gate_over(shared:, app:, budget: "brgen: 0\n")
    Dir.mktmpdir do |dir|
      plant(dir, "shared/config/locales/social.nb.yml", shared)
      plant(dir, "brgen/config/locales/nb.yml", app)
      budget_path = plant(dir, "locale_shadowing.yml", budget)
      with_constants(GATE, RAILS_ROOT: dir, APPS: %w[brgen], BUDGET: budget_path) { GATE.run }
    end
  end

  def locale(value)
    "nb:\n  nav:\n    brand_home: #{value}\n"
  end

  def test_a_key_the_engine_overrides_fails_against_a_zero_ceiling
    result = gate_over(shared: locale('"Home"'), app: locale('"Brgen home"'))

    refute result.ok?, "a shadowed key passed a ceiling of zero"
    assert_match(/1 shadowed key\(s\) exceeds ceiling 0/, result.failures.first)
    assert_match(/nb\.nav\.brand_home \(app "Brgen home" is dead, shared "Home" renders\)/, result.failures.first)
  end

  def test_the_same_key_agreeing_with_the_engine_passes
    result = gate_over(shared: locale('"Home"'), app: locale('"Home"'))

    assert result.ok?, result.failures.join(", ")
    assert_equal 1, result.checks_ran
  end

  # Under the ceiling is a win to record, not a failure to fix.
  def test_a_count_under_its_ceiling_warns
    result = gate_over(shared: locale('"Home"'), app: locale('"Home"'), budget: "brgen: 2\n")

    assert result.ok?, result.failures.join(", ")
    assert(result.warnings.any? { |line| line.match?(/under its 2 ceiling/) }, result.warnings.join(", "))
  end

  # No ceiling is not a pass at zero. An app absent from the budget file gets
  # counted and reported, so adding an app cannot silently exempt it.
  def test_an_app_with_no_ceiling_is_reported_rather_than_assumed_clean
    result = gate_over(shared: locale('"Home"'), app: locale('"Brgen home"'), budget: "amber: 0\n")

    assert(result.warnings.any? { |line| line.match?(/1 shadowed with no ceiling/) }, result.warnings.join(", "))
  end

  def test_a_valueless_key_in_the_engine_fails
    result = gate_over(shared: "nb:\n  nav:\n", app: locale('"Brgen home"'))

    refute result.ok?, "a bare key in shared passed"
    assert(result.failures.any? { |line| line.match?(/1 key\(s\) with no value \(nb\.nav\)/) },
           result.failures.join(", "))
    assert(result.failures.any? { |line| line.match?(/nil REPLACES a hash/) }, result.failures.join(", "))
  end

  # Only shared loads last, so only shared can do that damage. The same shape in
  # an app is a dead declaration, and failing on it would be failing on
  # something harmless.
  def test_a_valueless_key_in_an_app_only_warns
    result = gate_over(shared: locale('"Home"'), app: "nb:\n  nav:\n")

    assert result.ok?, result.failures.join(", ")
    assert(result.warnings.any? { |line| line.match?(/brgen.*1 key\(s\) with no value/) },
           result.warnings.join(", "))
  end

  def test_no_shared_locales_at_all_is_inconclusive
    result = Dir.mktmpdir do |dir|
      plant(dir, "brgen/config/locales/nb.yml", locale('"Brgen home"'))
      with_constants(GATE, RAILS_ROOT: dir, APPS: %w[brgen], BUDGET: File.join(dir, "none.yml")) { GATE.run }
    end

    assert_equal :inconclusive, result.outcome
    assert_match(/no shared locale files/, result.unchecked.first)
  end
end
