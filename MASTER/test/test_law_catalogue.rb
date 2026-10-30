# frozen_string_literal: true

require_relative "test_helper"
require_relative "../tools/audit/law_hygiene"
require_relative "../lib/operator/autofix_reach"
require_relative "../lib/operator/law_reach"

# The two checks over the law catalogue itself — tools/audit/law_hygiene.rb on
# its ids, aliases and metadata, Operator::AutofixReach and Operator::LawReach on
# whether a fix promise reaches code. One file because they read one subject:
# hygiene must not count the check names inside a law's config as laws, and
# reach must find a detector in law/ or the registry, not in laws.yml columns.
#
# Both directions are pinned throughout: no false positive, and every check
# still fires on the thing it exists to find.
class TestRuleCatalogue < Minitest::Test
  Law = Struct.new(:id, :detect, :fix, :severity, keyword_init: true) do
    def scannable? = !detect.nil?
  end

  # laws.yml's own shape: each law a top-level key carrying a priority and a statement. `catalogue` builds one
  # from rows with an id; the extra keys (learned_smells) sit beside them as they do in the file.
  def catalogue(*rows, **extra)
    entries = rows.to_h do |row|
      [row.fetch("id"), { "priority" => 1, "statement" => "s" }.merge(row.except("id"))]
    end
    # law_catalogue owns Law identity in laws.yml, so the fixture catalogues each row it declares.
    identities = { "law_catalogue" => { "entries" => entries.keys.to_h { |id| [id, {}] } } }
    entries.merge(identities, extra.transform_keys(&:to_s))
  end

  # A design law with a nested `config:` beside an ordinary one, shaped after
  # AUTOMATED_CSS_ANALYSIS: check names under `config.checks`, each with an `id`
  # and no tier or severity, because a check name is not a law.
  def body_with_checks
    catalogue(
      { "id" => "EIGHT_PX_RHYTHM", "tier" => "design", "severity" => "warning" },
      { "id" => "AUTOMATED_CSS_ANALYSIS", "tier" => "design", "severity" => "warning",
        "config" => { "checks" => [{ "id" => "eight_px_rhythm", "enforce" => ["Operator::ScaleLint"] },
                                   { "id" => "touch_target", "enforce" => ["TOUCH_TARGET_MIN"] }] } },
      learned_smells: [{ "id" => "magic_number", "pattern" => "\\d", "severity" => "warning" }],
    )
  end

  # Put the original method back rather than removing the override: module_function
  # leaves one singleton copy, and removing it takes the real reader with it — the
  # live-catalogue test below then errors on whichever seed runs it second.
  def with_body(body)
    original = Operator::LawHygiene.method(:master_laws)
    Operator::LawHygiene.define_singleton_method(:master_laws) { body }
    yield
  ensure
    Operator::LawHygiene.define_singleton_method(:master_laws, original)
  end

  def test_a_check_id_inside_a_laws_config_is_not_a_rule
    with_body(body_with_checks) do
      assert_empty Operator::LawHygiene.missing_metadata,
                   "config check names carry no tier because they are not laws"
      assert_empty Operator::LawHygiene.id_case_collisions,
                   "eight_px_rhythm is a check name under EIGHT_PX_RHYTHM's neighbour, not a second id"
    end
  end

  # The other direction, and the reason the walk cannot simply be narrowed to
  # laws.yml's `laws:` key: a learned smell reports under its own id, so it
  # collides with a registered rule exactly as another rule would.
  def test_a_learned_smell_still_counts_as_a_population
    body = catalogue({ "id" => "BARE_RESCUE", "tier" => "safety", "severity" => "error" },
                     learned_smells: [{ "id" => "bare_rescue", "pattern" => "rescue" }])
    with_body(body) do
      assert_equal [%w[BARE_RESCUE bare_rescue]], Operator::LawHygiene.id_case_collisions
      assert_equal ["bare_rescue"], Operator::LawHygiene.missing_metadata
    end
  end

  def test_a_rule_declaring_only_a_tier_has_metadata
    body = catalogue({ "id" => "A", "tier" => "design" }, { "id" => "B", "severity" => "info" }, { "id" => "C" })
    with_body(body) { assert_equal ["C"], Operator::LawHygiene.missing_metadata }
  end

  # Replaces the one Law population the hygiene checks below read.
  def with_populations(laws: {})
    hygiene = Operator::LawHygiene
    originals = { loaded_laws: hygiene.method(:loaded_laws) }
    hygiene.define_singleton_method(:loaded_laws) { laws }
    yield
  ensure
    originals.each { |name, method| hygiene.define_singleton_method(name, method) }
  end

  # Layered enforcement is one Law: its executable definition may contain a
  # deterministic detector and a semantic question, while the catalogue keeps
  # descriptive metadata only.
  def test_a_semantic_prompt_beside_a_detector_is_one_rule_at_two_depths
    body = catalogue({ "id" => "FAIL_VISIBLY", "tier" => "kernel", "severity" => "error" })
    laws = { FAIL_VISIBLY: Law.new(id: :FAIL_VISIBLY, detect: ->(_) { true }, fix: "Catch it.", severity: :error) }
    with_body(body) do
      with_populations(laws:) { assert_empty Operator::LawHygiene.cross_population_duplicates }
    end
  end

  def test_legacy_yaml_detector_fields_are_rejected
    body = catalogue({ "id" => "BARE_RESCUE", "tier" => "safety", "severity" => "error",
                       "detect_lexical" => "rescue$" })
    with_body(body) do
      error = assert_raises(RuntimeError) { Operator::LawHygiene.yaml_laws }
      assert_match(/legacy YAML detector fields are unsupported/, error.message)
    end
  end

  # A conflict is not that an id lives in two places, but that the two tell a
  # reader different things.
  def test_a_conflicting_fix_or_severity_is_reported_and_agreement_is_not
    body = catalogue({ "id" => "AGREES", "severity" => "error", "fix" => "Same words." },
                     { "id" => "DRIFTED", "severity" => "error", "fix" => "An older draft." },
                     { "id" => "LOUDER", "severity" => "info", "fix" => "Same words." })
    laws = { AGREES: Law.new(id: :AGREES, detect: ->(_) { true }, fix: "Same words.", severity: :error),
             DRIFTED: Law.new(id: :DRIFTED, detect: ->(_) { true }, fix: "What the law enforces.", severity: :error),
             LOUDER: Law.new(id: :LOUDER, detect: ->(_) { true }, fix: "Same words.", severity: :warn) }
    with_body(body) do
      with_populations(laws:) do
        conflicts = Operator::LawHygiene.statement_conflicts

        assert_equal %w[DRIFTED LOUDER], conflicts.map { |c| c[:law] }
        assert_equal ["fix"], conflicts.first[:reasons]
        assert_match(/info declared, warning enforced/, conflicts.last[:reasons].first)
      end
    end
  end

  # :warn in a law and "warning" in the catalogue are the same severity, and a
  # check that says otherwise reports every law in the tree.
  def test_warn_and_warning_are_one_severity
    body = catalogue({ "id" => "SAME", "severity" => "warning", "fix" => "One." })
    laws = { SAME: Law.new(id: :SAME, detect: ->(_) { true }, fix: "One.", severity: :warn) }
    with_body(body) { with_populations(laws:) { assert_empty Operator::LawHygiene.statement_conflicts } }
  end

  # An alias IS a retired id, so one naming nothing is correct and one naming a
  # live rule is the defect. Both asserted, because narrowing this check to
  # silence the second would turn it off rather than fix it.
  def test_an_alias_is_reported_only_when_its_subject_is_still_alive
    body = catalogue({ "id" => "DRY", "tier" => "principle", "aliases" => %w[duplicate_code retired_id] },
                     { "id" => "duplicate_code", "tier" => "smell" })
    with_body(body) do
      reported = Operator::LawHygiene.alias_shadows_live_law
      assert_equal [{ law: "DRY", alias_name: "duplicate_code" }], reported
    end
  end

  # The live catalogue, as an invariant rather than as today's numbers: these
  # three are at zero and zero is the floor recorded in law_ratchets.hygiene.
  def test_the_live_catalogue_is_clean
    report = Operator::LawHygiene.report
    assert_empty report[:id_case_collisions]
    assert_empty report[:alias_shadows_live_law]
    assert_empty report[:missing_metadata]
  end

  # --- autofix_reach: does a rule's fix promise reach code -------------------
  #
  # Detection is LawReach's question and these pin the three populations it has
  # to see. `mechanical` loads the laws rather than grepping for a literal
  # `Law.define(:ID)`, so generated laws such as law/prose.rb's are visible to it.

  def test_timeout = 120

  def ids(laws) = Operator::LawReach.mechanical(laws).map { |r| r["id"] }

  # FAIL_VISIBLY's detector lives in law/universal.rb and its laws.yml row
  # carries no detect_lexical.
  def test_a_detector_in_law_is_a_detector
    assert_equal ["FAIL_VISIBLY"], ids([{ "id" => "FAIL_VISIBLY", "autofix" => true }])
  end

  # TRAILING_WHITESPACE is a `check` Law under law/detectors/.
  def test_a_check_law_is_a_detector
    assert_equal ["TRAILING_WHITESPACE"], ids([{ "id" => "TRAILING_WHITESPACE", "autofix" => true }])
  end

  # folded_into names the rule that reports for this one. The id survives so
  # principle_map can trace it; the detector exists once, under the other name.
  def test_folded_into_reaches_the_rule_it_folded_into
    assert_equal ["MADE_UP_FOR_THIS_TEST"],
                 ids([{ "id" => "MADE_UP_FOR_THIS_TEST", "folded_into" => "FAIL_VISIBLY" }])
  end

  # The other direction: an id nothing anywhere detects must still come back empty,
  # or the check has been turned off rather than narrowed.
  def test_an_id_no_population_knows_is_not_mechanical
    assert_empty ids([{ "id" => "NO_SUCH_RULE_ANYWHERE" }])
  end

  # Written so that fixing a law keeps it green: raise a severity, add a detector or say `autofix: false` and this
  # passes. It cannot be satisfied by a rule going quiet.
  def test_no_autofix_claim_is_unreportable
    stranded = Operator::AutofixReach.bare_true.reject { |row| row[:detected] }

    assert_empty stranded.map { |row| row[:rule] },
                 "these claim a mechanical fix and nothing ever reports them, so the fix " \
                 "can never be applied — raise the severity, give one a detector, or say false"
  end

  def test_no_named_transform_is_dangling
    assert_empty Operator::AutofixReach.dangling.map { |d| "#{d[:rule]} -> #{d[:transform]}" }
  end

  def test_law_reach_counts_executable_laws_not_the_eight_policy_laws
    rows = Operator::LawReach.laws

    assert_operator rows.size, :>, 100
    assert_includes rows.map { |row| row["id"] }, "FAIL_VISIBLY"
    assert_includes rows.map { |row| row["id"] }, "TRAILING_WHITESPACE"
    assert_equal [], Operator::LawReach.unreachable(rows)
  end
end
