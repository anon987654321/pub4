# frozen_string_literal: true

require_relative "test_helper"
require_relative "../tools/rule_hygiene"
require_relative "../tools/autofix_reach"
require_relative "../tools/rule_reach"

# The two gates over the rule catalogue itself — tools/rule_hygiene.rb on its
# ids, aliases and metadata, tools/autofix_reach.rb on whether a rule fix
# promise reaches code. One file because they read one subject, and because
# each was measuring itself rather than the catalogue in the same way: hygiene
# counted the check names inside a rule config as rules, and autofix_reach
# asked whether a rule can be FOUND by reading three columns in rules.yml when
# ten of the twelve it named have a detector in law/ or the registry.
#
# Both directions are pinned throughout: the false positives are gone AND every
# check still fires on the thing it exists to find.

class TestRuleCatalogue < Minitest::Test
  # A design rule with a nested `config:` beside two ordinary rules. Shaped after
  # AUTOMATED_CSS_ANALYSIS, which is where the false positives came from: eight
  # check names under `config.checks`, each with an `id` and — correctly — no
  # tier and no severity, because a check name is not a rule.
  BODY = {
    "rules" => [
      { "id" => "EIGHT_PX_RHYTHM", "tier" => "design", "severity" => "warning" },
      { "id" => "AUTOMATED_CSS_ANALYSIS", "tier" => "design", "severity" => "warning",
        "config" => { "checks" => [{ "id" => "eight_px_rhythm", "enforce" => ["Pub4::ScaleLint"] },
                                   { "id" => "touch_target", "enforce" => ["TOUCH_TARGET_MIN"] }] } },
    ],
    "learned_smells" => [
      { "id" => "magic_number", "pattern" => "\\d", "severity" => "warning" },
    ],
  }.freeze

  # Put the original method back rather than removing the override: module_function
  # leaves one singleton copy, and removing it takes the real reader with it — the
  # live-catalogue test below then errors on whichever seed runs it second.
  def with_body(body)
    original = Pub4::RuleHygiene.method(:master_rules)
    Pub4::RuleHygiene.define_singleton_method(:master_rules) { body }
    yield
  ensure
    Pub4::RuleHygiene.define_singleton_method(:master_rules, original)
  end

  def test_a_check_id_inside_a_rules_config_is_not_a_rule
    with_body(BODY) do
      assert_empty Pub4::RuleHygiene.missing_metadata,
                   "config check names carry no tier because they are not rules"
      assert_empty Pub4::RuleHygiene.id_case_collisions,
                   "eight_px_rhythm is a check name under EIGHT_PX_RHYTHM's neighbour, not a second id"
    end
  end

  # The other direction, and the reason the walk cannot simply be narrowed to
  # rules.yml's `rules:` key: a learned smell reports under its own id, so it
  # collides with a registered rule exactly as another rule would.
  def test_a_learned_smell_still_counts_as_a_population
    body = { "rules" => [{ "id" => "BARE_RESCUE", "tier" => "safety", "severity" => "error" }],
             "learned_smells" => [{ "id" => "bare_rescue", "pattern" => "rescue" }] }
    with_body(body) do
      assert_equal [%w[BARE_RESCUE bare_rescue]], Pub4::RuleHygiene.id_case_collisions
      assert_equal ["bare_rescue"], Pub4::RuleHygiene.missing_metadata
    end
  end

  def test_a_rule_declaring_only_a_tier_has_metadata
    body = { "rules" => [{ "id" => "A", "tier" => "design" }, { "id" => "B", "severity" => "info" },
                         { "id" => "C" }] }
    with_body(body) { assert_equal ["C"], Pub4::RuleHygiene.missing_metadata }
  end

  # An alias IS a retired id, so one naming nothing is correct and one naming a
  # live rule is the defect. Both asserted, because narrowing this check to
  # silence the second would turn it off rather than fix it.
  def test_an_alias_is_reported_only_when_its_subject_is_still_alive
    body = { "rules" => [{ "id" => "DRY", "tier" => "principle", "aliases" => %w[duplicate_code retired_id] },
                         { "id" => "duplicate_code", "tier" => "smell" }] }
    with_body(body) do
      reported = Pub4::RuleHygiene.alias_shadows_live_rule
      assert_equal [{ rule: "DRY", alias_name: "duplicate_code" }], reported
    end
  end

  # The live catalogue, as an invariant rather than as today's numbers: these
  # three are at zero and zero is the floor recorded in rule_ratchets.hygiene.
  def test_the_live_catalogue_is_clean
    report = Pub4::RuleHygiene.report
    assert_empty report[:id_case_collisions]
    assert_empty report[:alias_shadows_live_rule]
    assert_empty report[:missing_metadata]
  end

  # --- autofix_reach: does a rule's fix promise reach code -------------------
  #
  # Detection is RuleReach's question and these pin the three populations it has
  # to see. `mechanical` loads the laws rather than grepping for a literal
  # `Law.define(:ID)`, which is why law/prose.rb's four generated rules are
  # visible to it and were not to the grep that came before.

  def test_timeout = 120

  def ids(rules) = Pub4::RuleReach.mechanical(rules).map { |r| r["id"] }

  # FAIL_VISIBLY's detector lives in law/universal.rb and its rules.yml row
  # carries no detect_lexical — the shape the old count called undetectable.
  def test_a_detector_in_law_is_a_detector
    assert_equal ["FAIL_VISIBLY"], ids([{ "id" => "FAIL_VISIBLY", "autofix" => true }])
  end

  # TRAILING_WHITESPACE exists only as a RuleDSL class, the third population.
  def test_a_detector_in_the_registry_is_a_detector
    assert_equal ["TRAILING_WHITESPACE"], ids([{ "id" => "TRAILING_WHITESPACE", "autofix" => true }])
  end

  # folded_into names the rule that reports for this one. The id survives so
  # principle_map can trace it; the detector exists once, under the other name.
  def test_folded_into_reaches_the_rule_it_folded_into
    assert_equal ["MADE_UP_FOR_THIS_TEST"],
                 ids([{ "id" => "MADE_UP_FOR_THIS_TEST", "folded_into" => "FAIL_VISIBLY" }])
  end

  # The other direction. Narrowing this to silence the twelve would have turned
  # the check off, so an id nothing anywhere detects must still come back empty.
  def test_an_id_no_population_knows_is_not_mechanical
    assert_empty ids([{ "id" => "NO_SUCH_RULE_ANYWHERE" }])
  end

  # The invariant the correction bought, written so that fixing a rule keeps it
  # green: raise a severity, add a detector or say `autofix: false` and this
  # passes. It cannot be satisfied by a rule going quiet.
  def test_no_autofix_claim_is_unreportable
    stranded = Pub4::AutofixReach.bare_true.reject { |row| row[:detected] }

    assert_empty stranded.map { |row| row[:rule] },
                 "these claim a mechanical fix and nothing ever reports them, so the fix " \
                 "can never be applied — raise the severity, give one a detector, or say false"
  end

  def test_no_named_transform_is_dangling
    assert_empty Pub4::AutofixReach.dangling.map { |d| "#{d[:rule]} -> #{d[:transform]}" }
  end
end
