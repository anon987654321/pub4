# frozen_string_literal: true

require_relative "test_helper"

class TestLawBridgeRule < Minitest::Test
  def rule = Master::Review::Scan::Rules::LawBridgeRule.new(root: Master::ROOT)

  def test_a_law_reaches_the_scanner
    findings = rule.check("var x = 1;\n", path: "app/thing.js")
    assert findings.any?, "NO_VAR did not reach the scanner through law/"
    assert_match(/NO_VAR/, findings.map(&:message).join)
  end

  # The language filter is the difference between a rule and a nuisance: a JS
  # law must not fire on Ruby that happens to contain the same characters.
  def test_language_scoping_is_honoured
    assert_empty rule.check("var_name = 1\n", path: "lib/thing.rb").select { |f| f.message.include?("NO_VAR") }
  end

  # path narrows a law to one tree. A migration law has no business judging a
  # controller, and the yml column that used to carry this was easy to drop.
  #
  # The filters are written with leading slashes ("/db/migrate/"), so they match
  # the absolute paths the scanner expands before handing them over. A caller
  # passing a repo-relative path gets no path-scoped law at all — silently, since
  # a law that does not apply reports nothing. WriteGuard passes `path.to_s`,
  # which is the one place that could arrive relative, so both forms are pinned
  # here rather than left to be discovered by a rule that stopped firing.
  def test_path_scoping_matches_the_absolute_paths_the_scanner_passes
    code = "add_reference :posts, :user\n"
    absolute = "/repo/RAILS/brgen/db/migrate/20260101_x.rb"
    assert rule.check(code, path: absolute).any? { |f| f.message.include?("MIGRATION_ADD_REFERENCE_NO_FK") }
    assert_empty rule.check(code, path: "/repo/app/models/post.rb").select { |f| f.message.include?("MIGRATION_ADD") }
  end

  def test_a_relative_path_is_the_known_blind_spot
    code = "add_reference :posts, :user\n"
    relative = rule.check(code, path: "db/migrate/20260101_x.rb")
    assert_empty relative.select { |f| f.message.include?("MIGRATION_ADD") },
                 "path filters are anchored with a leading slash; if this starts passing, " \
                 "they were re-anchored and the comment above is stale"
  end

  # Severity travels with the law rather than being reassigned at the bridge,
  # so an :error law cannot arrive as a warning.
  def test_severity_survives_the_bridge
    finding = rule.check("var x = 1;\n", path: "app/thing.js").find { |f| f.message.include?("NO_VAR") }
    assert_equal :error, finding.severity
  end

  # Every law proved itself against its own fixtures at load. If that stops
  # being true the bridge should not be the place it is discovered, but a rule
  # arriving here unproven would mean prove! had been skipped.
  #
  # Three parts still, and the third is one of three kinds: a detector, a
  # question for a model, or a practice. Requiring `detect` specifically was the
  # rule that kept 47 conduct rules in soul.yml — no regex reads "one SSH
  # session" off a file, so demanding one excluded exactly the rules it could
  # not describe.
  def test_every_loaded_law_carries_its_fixtures
    rule # force the load
    unproven = Law.rules.values.reject { |r| r.bad && r.good && (r.detect || r.ask || r.practice) }
    assert_empty unproven.map(&:id), "laws without all three parts reached the registry"
  end
end
