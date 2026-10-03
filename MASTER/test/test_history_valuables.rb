# frozen_string_literal: true

require_relative "test_helper"
require_relative "../tools/history_valuables"

# TODO.md closes an entry by deleting it, so its deletions must not read as
# lost valuables; the same line deleted from any other file still must.
class TestHistoryValuables < Minitest::Test
  LOG = <<~LOG
    commit aaaa1111
    diff --git a/TODO.md b/TODO.md
    -12. **`MASTER` rcctl restart after deploy.** Closed.
    diff --git a/MASTER/lib/io/relayd.rb b/MASTER/lib/io/relayd.rb
    -  def restart = system("rcctl", "restart", "relayd")
    --- a/MASTER/lib/io/relayd.rb
    -
  LOG

  def test_a_closed_backlog_entry_is_not_a_lost_valuable
    files = HistoryValuables.hits(LOG).map { |hit| hit[:file] }

    refute_includes files, "TODO.md"
  end

  def test_the_same_kind_of_line_deleted_from_code_is_reported
    hit = HistoryValuables.hits(LOG).find { |row| row[:file] == "MASTER/lib/io/relayd.rb" }

    refute_nil hit
    assert_equal "aaaa1111", hit[:commit]
    assert_includes hit[:line], "def restart"
  end

  def test_file_headers_and_blank_deletions_are_not_lines
    assert_nil HistoryValuables.deleted_text("--- a/MASTER/lib/io/relayd.rb")
    assert_nil HistoryValuables.deleted_text("-   ")
  end
end
