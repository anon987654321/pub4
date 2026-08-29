# frozen_string_literal: true

# Prose is where the drift always happens, because nothing parses prose.
#
# TODO.md held a copy of spine.yml's raise log and drifted from it. The commit
# that fixed that (f34907d40) says so in its own message — and within a day
# DECISIONS.md was left claiming a rebaseline to 38823 against spine.yml's
# 38811, by the session that had just read the fix. Twice in two days, same
# defect, same file pair.

require "minitest/autorun"
require "yaml"
require_relative "../tools/doc_citations"

class TestDocCitations < Minitest::Test
  def self.report = @report ||= Pub4::DocCitations.run

  def setup
    @report = self.class.report
  end

  def test_no_document_quotes_a_number_data_no_longer_holds
    drifted = @report["findings"].map { |row| "#{row['doc']}: #{row['message']}" }

    assert_empty drifted,
                 "prose disagrees with data/. Fix the document, or the data file if the " \
                 "document is right:\n  #{drifted.join("\n  ")}"
  end

  # A checker that has stopped finding anything to check reports clean forever.
  def test_the_checker_is_reading_documents_and_data
    assert_operator @report["docs"], :>, 40, "only #{@report['docs']} documents seen"
    # Floor, not a target. It was 6 until 2026-08-12, when fixing seven stale
    # `core_files: 6` references removed most of them — rewriting prose to drop
    # the number is a real loss of coverage, so the floor is asserted rather than
    # quietly followed downward.
    #
    # 4 -> 3 on 2026-08-14, and this is the case that comment is about, so it gets
    # the argument it asks for. DECISIONS.md carried a `cite:` on the spine ceiling
    # inside the sentence "It has since been raised three times, to 38869" — a
    # claim about a past sequence, wearing a marker that holds it to the value
    # data/ currently has. Every later raise turned a true statement about history
    # into a failing claim about the present, and it drifted within two days.
    #
    # So this is not prose dropping a number to dodge the gate: the citation was
    # wrong to exist, because the sentence was never asserting a current value.
    # The story stayed and the figure moved to data/spine.yml, which is the one
    # place that owns it. Coverage genuinely fell by one and the floor follows,
    # visibly.
    assert_operator @report["quotations"] + @report["citations"], :>=, 3,
                    "only #{@report['quotations']} quotation(s) and #{@report['citations']} " \
                    "citation(s) found — the checker stopped matching"
    assert_includes Pub4::DocCitations.keys.keys, "core_files",
                    "core_files is no longer recognised as a citable key"
  end

  def test_a_citation_resolves_against_data
    value, error = Pub4::DocCitations.resolve("data/spine.yml", "spine.core_files")

    live = YAML.safe_load_file(File.expand_path("../data/spine.yml", __dir__)).dig("spine", "core_files")

    assert_nil error
    # Against the file, not a literal. This asserted "6" and broke the day
    # core_files was raised — a test that hardcodes the value whose citation it
    # is checking is itself a third copy of that value.
    assert_equal live.to_s, value
  end

  # Both halves of a citation must be able to fail: a wrong number, and a marker
  # pointing at something that no longer exists.
  def test_a_citation_that_cannot_resolve_is_a_finding
    _, missing_file = Pub4::DocCitations.resolve("data/no_such_file.yml", "a.b")
    _, missing_key = Pub4::DocCitations.resolve("data/spine.yml", "spine.no_such_key")

    assert_equal "no such file", missing_file
    assert_equal "no such key", missing_key
  end

  def test_a_wrong_number_before_a_marker_is_a_finding
    live, = Pub4::DocCitations.resolve("data/spine.yml", "spine.core_files")
    wrong = live.to_i + 1
    findings = Pub4::DocCitations.citation_findings(
      "TEST.md", 1, "data/spine.yml", "spine.core_files", "a ceiling of #{wrong} "
    )

    assert_equal 1, findings.size
    assert_includes findings.first["message"], "cites spine.core_files as #{wrong}"
  end
end
