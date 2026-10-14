# frozen_string_literal: true

require_relative "test_helper"
require "open3"

# pub4 has one authoritative queue. A child TODO.md is a second source of
# truth even when it is linked from the root; prevent the old layout returning.
class TestSingleBacklogContract < Minitest::Test
  ROOT = File.expand_path("../..", __dir__)

  def test_root_todo_is_the_only_tracked_todo_file
    output, status = Open3.capture2(
      "git", "-C", ROOT, "ls-files", "--", "TODO.md", "**/TODO.md"
    )

    assert status.success?, "could not inspect tracked backlog paths"
    paths = output.lines.map(&:strip).reject(&:empty?).uniq.sort
    assert_equal ["TODO.md"], paths
  end
end
