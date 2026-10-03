# frozen_string_literal: true

require "minitest/autorun"
require "tmpdir"
require_relative "gate_fixture"
require_relative "../../../MASTER/gates/lib/source/locale_shadowing"

# An app overriding a shared translation, held to a ceiling.
#
# shared/config/locales loads once, ahead of each app, so when both define a
# key the app's value renders and shared's is dead in that app. The count is
# the app's overrides, and a new one should be a decision.
#
# The second half is worse and invisible to the first: a key with no value
# parses as nil, and nil REPLACES a hash in I18n's deep merge, so one bare
# `nav:` wipes every label merged under it before. A shadowing check compares
# values that disagree, and a key resolving to nothing disagrees with nobody.
#
# The fixture tree, app list and budget file are passed as keywords. The app is
# named brgen because the orphan half walks a hardcoded tree list.
class LocaleShadowingGateTest < Minitest::Test
  include GateFixture

  GATE = Deploy::LocaleShadowingGate

  def gate_over(shared:, app:, budget: "brgen: 0\n")
    Dir.mktmpdir do |dir|
      plant(dir, "RAILS/shared/config/locales/social.nb.yml", shared)
      plant(dir, "RAILS/brgen/config/locales/nb.yml", app)
      budget_path = plant(dir, "locale_shadowing.yml", budget)
      GATE.run(root: dir, apps: %w[brgen], budget: budget_path)
    end
  end

  def locale(value)
    "nb:\n  nav:\n    brand_home: #{value}\n"
  end

  def test_missing_budget_is_inconclusive
    result = gate_with_budget(shared: locale('"Home"'), app: locale('"Brgen home"'), budget: nil)
    assert_equal :inconclusive, result.outcome
  end

  def test_unreadable_budget_is_inconclusive
    Dir.mktmpdir do |dir|
      plant(dir, "RAILS/shared/config/locales/social.nb.yml", locale('"Home"'))
      plant(dir, "RAILS/brgen/config/locales/nb.yml", locale('"Brgen home"'))
      budget = plant(dir, "locale_shadowing.yml", "not: [valid")
      result = GATE.run(root: dir, apps: %w[brgen], budget:)
      assert_equal :inconclusive, result.outcome
    end
  end

  def gate_with_budget(shared:, app:, budget:)
    Dir.mktmpdir do |dir|
      plant(dir, "RAILS/shared/config/locales/social.nb.yml", shared)
      plant(dir, "RAILS/brgen/config/locales/nb.yml", app)
      budget_path = budget && plant(dir, "locale_shadowing.yml", budget)
      GATE.run(root: dir, apps: %w[brgen], budget: budget_path || File.join(dir, "missing.yml"))
    end
  end

  def test_unreadable_locale_file_is_inconclusive
    Dir.mktmpdir do |dir|
      plant(dir, "RAILS/shared/config/locales/social.nb.yml", "nb:\n  nav:\n    home: \"Home\"\n")
      plant(dir, "RAILS/shared/config/locales/broken.yml", "nb: [broken")
      plant(dir, "RAILS/brgen/config/locales/nb.yml", "nb:\n  nav:\n    home: \"Home\"\n")
      budget = plant(dir, "locale_shadowing.yml", "brgen: 0\n")
      result = GATE.run(root: dir, apps: %w[brgen], budget:)
      assert_equal :inconclusive, result.outcome
    end
  end

  def test_an_app_override_of_a_shared_key_fails_against_a_zero_ceiling
    result = gate_over(shared: locale('"Home"'), app: locale('"Brgen home"'))

    refute result.ok?, "an override passed a ceiling of zero"
    assert_match(/1 app override\(s\) of shared keys exceeds ceiling 0/, result.failures.first)
    assert_match(/nb\.nav\.brand_home \(app "Brgen home" renders, shared "Home" is dead here\)/, result.failures.first)
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

  # The app loads after shared, so its bare key wipes shared's subtree there.
  def test_a_valueless_key_in_an_app_fails
    result = gate_over(shared: locale('"Home"'), app: "nb:\n  nav:\n")

    refute result.ok?, "a bare key in an app passed"
    assert(result.failures.any? { |line| line.match?(/brgen.*1 key\(s\) with no value \(nb\.nav\)/) },
           result.failures.join(", "))
  end

  def test_no_shared_locales_at_all_is_inconclusive
    result = Dir.mktmpdir do |dir|
      plant(dir, "RAILS/brgen/config/locales/nb.yml", locale('"Brgen home"'))
      GATE.run(root: dir, apps: %w[brgen], budget: File.join(dir, "none.yml"))
    end

    assert_equal :inconclusive, result.outcome
    assert_match(/no shared locale files/, result.unchecked.first)
  end
end
