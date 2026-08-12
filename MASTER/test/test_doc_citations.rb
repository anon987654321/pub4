# frozen_string_literal: true

# Prose is where the drift always happens, because nothing parses prose.
#
# DEBT.md held a copy of spine.yml's raise log and drifted from it. The commit
# that fixed that (f34907d40) says so in its own message — and within a day
# DECISIONS.md was left claiming a rebaseline to 38823 against spine.yml's
# 38811, by the session that had just read the fix. Twice in two days, same
# defect, same file pair.

require "minitest/autorun"
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
    assert_operator @report["quotations"] + @report["citations"], :>=, 6,
                    "only #{@report['quotations']} quotation(s) and #{@report['citations']} " \
                    "citation(s) found — the checker stopped matching"
    assert_includes Pub4::DocCitations.keys.keys, "core_files",
                    "core_files is no longer recognised as a citable key"
  end

  def test_a_citation_resolves_against_data
    value, error = Pub4::DocCitations.resolve("data/spine.yml", "spine.core_files")

    assert_nil error
    assert_equal "6", value
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
    findings = Pub4::DocCitations.citation_findings(
      "TEST.md", 1, "data/spine.yml", "spine.core_files", "a ceiling of 7 "
    )

    assert_equal 1, findings.size
    assert_includes findings.first["message"], "cites spine.core_files as 7"
  end
end
