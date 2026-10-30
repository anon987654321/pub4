# frozen_string_literal: true

# Every Law that carries worked examples must satisfy them, the way the scanner
# reads them.
#
# The common failure is a law matching a pattern adjacent to the one it
# enforces — Time.now for a Time.zone law, an @media condition read as an
# element width — a false *positive*: the law fires where the law is
# satisfied. A rule that carries the case it must not fire on cannot drift that
# way in silence, which is why `good` matters more here than `bad`.
#
# Law::Definition#prove! already refuses to load a Law whose fixtures fail. This
# reads them through the scanner's own object for each Law (LawTree.find), so the
# language and path gating the scanner applies is the gating they are proved under.

require_relative "test_helper"
require_relative "../lib/review/scan/law_tree"

class TestLawFixtures < Minitest::Test
  def self.fixtured
    @fixtured ||= Master::Review::Scan::LawTree.definitions.select do |law|
      law.scannable? && !law.proved_by && law.bad && (law.check || law.detector || law.example_path)
    end
  end

  def findings_for(law, source)
    Master::Review::Scan::LawTree.find(law.id).check(source, path: law.proof_path) || []
  end

  def test_each_fixtured_law_fires_on_its_positive_example
    failures = self.class.fixtured.filter_map do |law|
      "#{law.id} did not fire on its own bad example" if findings_for(law, law.bad).empty?
    end

    assert_empty failures, failures.join("\n")
  end

  # The direction that actually breaks.
  def test_no_fixtured_law_fires_on_its_negative_example
    failures = self.class.fixtured.filter_map do |law|
      found = findings_for(law, law.good)
      next if found.empty?

      "#{law.id} fired on its good example — #{found.map { |f| f[:message] }.first(2).join('; ')}"
    end

    assert_empty failures, failures.join("\n")
  end

  # A harness that silently stops finding Laws passes forever.
  def test_the_harness_still_sees_laws
    assert_operator Master::Review::Scan::LawTree.ids.size, :>, 400,
                    "only #{Master::Review::Scan::LawTree.ids.size} Laws defined — law/ stopped loading"
    assert_operator self.class.fixtured.size, :>=, 100,
                    "only #{self.class.fixtured.size} Laws carry examples — fixtures stopped being read"
  end

  # A `check` Law with no worked example and no test that proves it. This
  # ceiling only moves down (data/laws.yml, law_ratchets.fixture_debt).
  def test_the_unfixtured_checks_only_shrink
    unfixtured = Master::Review::Scan::LawTree.definitions.select { |law| law.check && law.bad.nil? && !law.proved_by }
    ceiling = Master.law("law_ratchets").fetch("fixture_debt").fetch("without_fixtures")
    assert_operator unfixtured.size, :<=, ceiling,
      "a new check Law without bad/good fixtures — carry the worked examples, the way every Law must: " \
      "#{unfixtured.map(&:id).join(', ')}"
    return unless unfixtured.size < ceiling

    puts "rule_fixture_debt: #{unfixtured.size} < ceiling #{ceiling} — record the new low in data/laws.yml law_ratchets.fixture_debt"
  end

  # Comment lines are blanked before the scan and a finding keeps the line it is on, so blanking must
  # not take the newlines of the blank lines above a comment with it.
  def test_time_zone_finding_reports_its_own_line_after_blank_lines_and_comments
    law = Master::Review::Scan::LawTree.find(:TIME_ZONE_UNSAFE)
    source = "a = 1\n\n\n# a comment\n\n" + format("b = %s.now\n", "Time")

    found = law.check(source, path: "/repo/app/models/example.rb")

    assert_equal [6], found.map { |finding| finding[:line] }
  end
end
