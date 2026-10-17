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
      ["6", "second open item"]
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
end
