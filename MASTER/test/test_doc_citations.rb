# frozen_string_literal: true

# Prose is where the drift always happens, because nothing parses prose. The
# same defect reached the same file pair twice in two days, once from the
# session that had just read the fix.

require "minitest/autorun"
require "yaml"
require_relative "../tools/doc_citations"

class TestDocCitations < Minitest::Test
  def self.report = @report ||= Operator::DocCitations.run

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
    # Floor, not a target: rewriting prose to drop a quoted number is a real loss
    # of coverage, so the floor is asserted rather than quietly followed downward.
    # It stands at the one quotation the live documents carry, START_HERE.md's
    # `core_files`.
    assert_operator @report["quotations"] + @report["citations"], :>=, 1,
                    "only #{@report['quotations']} quotation(s) and #{@report['citations']} " \
                    "citation(s) found — the checker stopped matching"
    assert_includes Operator::DocCitations.keys.keys, "core_files",
                    "core_files is no longer recognised as a citable key"
  end

  # With one live quotation the floor above proves little on its own, so the
  # matcher proves itself on a planted body: a right value passes, a wrong one is
  # a finding.
  def test_a_quotation_is_checked_against_data
    live, = Operator::DocCitations.resolve("data/spine.yml", "spine.core_files")
    findings = []

    body = "core_files: #{live} and core_files: #{live.to_i + 1}"
    count = Operator::DocCitations.check_quotations("TEST.md", body, findings)

    assert_equal 2, count
    assert_equal 1, findings.size
    assert_includes findings.first["message"], "quotes core_files: #{live.to_i + 1}"
  end

  def test_a_citation_resolves_against_data
    value, error = Operator::DocCitations.resolve("data/spine.yml", "spine.core_files")

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
    _, missing_file = Operator::DocCitations.resolve("data/no_such_file.yml", "a.b")
    _, missing_key = Operator::DocCitations.resolve("data/spine.yml", "spine.no_such_key")

    assert_equal "no such file", missing_file
    assert_equal "no such key", missing_key
  end

  def test_a_wrong_number_before_a_marker_is_a_finding
    live, = Operator::DocCitations.resolve("data/spine.yml", "spine.core_files")
    wrong = live.to_i + 1
    findings = Operator::DocCitations.citation_findings(
      "TEST.md", 1, "data/spine.yml", "spine.core_files", "a ceiling of #{wrong} "
    )

    assert_equal 1, findings.size
    assert_includes findings.first["message"], "cites spine.core_files as #{wrong}"
  end
end
