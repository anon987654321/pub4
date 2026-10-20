# frozen_string_literal: true

require_relative "test_helper"
require "open3"

# Operator-only work lives in data/operator_seams.yml and nowhere else. A
# TODO.md anywhere is a second queue; prevent the old layout returning.
class TestSingleBacklogContract < Minitest::Test
  ROOT = File.expand_path("../..", __dir__)
  SEAM_KEYS = %w[evidence id needs tree].freeze

  def test_no_tracked_todo_file_exists
    output, status = Open3.capture2("git", "-C", ROOT, "ls-files", "--", "TODO.md", "**/TODO.md")

    assert status.success?, "could not inspect tracked backlog paths"
    assert_empty output.split
  end

  def test_every_seam_names_its_tree_need_and_evidence
    seams = YAML.safe_load_file(File.join(ROOT, "MASTER", "data", "operator_seams.yml")).fetch("seams")

    refute_empty seams
    assert_equal seams.size, seams.uniq { |seam| seam.fetch("id") }.size
    assert_empty seams.reject { |seam| seam.keys.sort == SEAM_KEYS }
  end
end
