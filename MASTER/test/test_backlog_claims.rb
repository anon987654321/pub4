# frozen_string_literal: true

require_relative "test_helper"
require_relative "../tools/backlog_claims"

class TestBacklogClaims < Minitest::Test
  ROOT = File.expand_path("../..", __dir__)

  def test_parser_reads_open_checkboxes_and_ignores_completed_items
    source = <<~MARKDOWN
      # Backlog
      1. Legacy numbered item
      - [ ] first open item
      - [x] completed item
      - [X] also completed
      - [ ] second open item
    MARKDOWN

    assert_equal [
      ["3", "first open item"],
      ["6", "second open item"],
    ], BacklogClaims.parse_items(source)
  end

  def test_current_backlog_item_count_matches_checkbox_source
    source = File.read(File.join(ROOT, "TODO.md"))
    expected = source.lines.count { |line| /^\s*-\s+\[ \]\s+/.match?(line) }

    items = BacklogClaims.items

    assert_operator expected, :>, 0, "the backlog must not silently become empty"
    assert_equal expected, items.size
    assert items.all? { |line_number, text| line_number.to_i.positive? && !text.empty? }
  end

  def test_verdict_checks_missing_paths_even_when_a_line_citation_is_valid
    BacklogClaims.stub(:tracked, Set.new(["MASTER/source.rb"])) do
      BacklogClaims.stub(:line_count, 12) do
        result = BacklogClaims.verdict(
          "MASTER/source.rb:10 is used by STUDIO/missing.rb"
        )

        assert_equal :citation_findings, result.first
        assert_includes result.last, "missing path: STUDIO/missing.rb"
      end
    end
  end

  def test_unreadable_line_citation_is_inconclusive_not_stale
    BacklogClaims.stub(:tracked, Set.new(["MASTER/unreadable.rb"])) do
      BacklogClaims.stub(:line_count, nil) do
        result = BacklogClaims.verdict("MASTER/unreadable.rb:5")

        assert_equal :citation_findings, result.first
        assert_includes result.last, "inconclusive line: could not read MASTER/unreadable.rb"
      end
    end
  end
end
