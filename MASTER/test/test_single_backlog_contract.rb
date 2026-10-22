# frozen_string_literal: true

require_relative "test_helper"
require "open3"

# There is one cross-tree backlog at the repository root. Structured
# operator decisions live in operator_seams.yml; nested TODO files are second
# work queues and must not be introduced.
class TestSingleBacklogContract < Minitest::Test
  ROOT = File.expand_path("../..", __dir__)
  SEAM_KEYS = %w[evidence id needs tree].freeze

  def test_only_the_root_backlog_is_tracked
    output, status = Open3.capture2("git", "-C", ROOT, "ls-files", "--", "TODO.md", "**/TODO.md")

    assert status.success?, "could not inspect tracked backlog paths"
    assert_equal ["TODO.md"], output.split.sort
  end

  def test_every_seam_names_its_tree_need_and_evidence
    seams = Master.load_yaml(File.join(ROOT, "MASTER", "data", "operator_seams.yml")).fetch("seams")

    refute_empty seams
    assert_equal seams.size, seams.uniq { |seam| seam.fetch("id") }.size
    assert_empty seams.reject { |seam| seam.keys.sort == SEAM_KEYS }
  end
end
