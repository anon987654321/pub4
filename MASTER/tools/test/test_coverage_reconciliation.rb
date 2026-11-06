# frozen_string_literal: true

require "minitest/autorun"
require "tmpdir"
require "fileutils"
require_relative "../coverage_reconciliation"

# The rule the checks README paid for: plant the defect, assert red and
# named, remove it, assert green, and drive the tool once against a gutted
# input. Here that means three fixtures — a file no instrument sees under a
# complete map (must fail), the same tree fully covered (must pass), and the
# same gap under a map that declares itself partial (must be inconclusive,
# never silently green).
class TestCoverageReconciliation < Minitest::Test
  def setup
    @repo = Dir.mktmpdir
    FileUtils.mkdir_p(File.join(@repo, "MASTER", "checks", "data"))
    FileUtils.mkdir_p(File.join(@repo, "RAILS", "amber", "app", "assets", "stylesheets"))
  end

  def teardown
    FileUtils.remove_entry(@repo)
  end

  def write_map(complete:, globs:)
    path = File.join(@repo, "MASTER", "checks", "data", "coverage_map.yml")
    File.write(path, <<~YAML)
      schema: 1
      name: coverage_map
      complete: #{complete}
      roots:
        - RAILS
      instruments:
        - name: fixture_instrument
          globs:
            #{globs}
    YAML
    path
  end

  def run_tool(map_path)
    tool = Deploy::CoverageReconciliation.new(map_path:, repo_root: @repo)
    result = tool.run
    [result, tool]
  end

  def test_complete_map_fails_on_a_file_no_instrument_sees
    File.write(File.join(@repo, "RAILS", "amber", "app", "assets", "stylesheets", "covered.scss"), "a {}")
    File.write(File.join(@repo, "RAILS", "amber", "app", "assets", "stylesheets", "orphan.scss"), "b {}")

    result, tool = run_tool(write_map(complete: true, globs: '- "RAILS/amber/app/assets/stylesheets/covered.scss"'))

    assert_equal :failed, result.outcome
    assert_includes tool.uncovered.map { |p| File.basename(p) }, "orphan.scss"
    assert_includes result.failures.first.to_s, "orphan.scss", "the failure must name the file it is failing on"
  end

  def test_complete_map_passes_when_everything_is_covered
    File.write(File.join(@repo, "RAILS", "amber", "app", "assets", "stylesheets", "covered.scss"), "a {}")

    result, tool = run_tool(write_map(complete: true, globs: '- "RAILS/amber/app/assets/stylesheets/*.scss"'))

    assert_equal :passed, result.outcome
    assert_empty tool.uncovered
  end

  def test_partial_map_is_inconclusive_even_with_gaps
    File.write(File.join(@repo, "RAILS", "amber", "app", "assets", "stylesheets", "covered.scss"), "a {}")
    File.write(File.join(@repo, "RAILS", "amber", "app", "assets", "stylesheets", "orphan.scss"), "b {}")

    result, tool = run_tool(write_map(complete: false, globs: '- "RAILS/amber/app/assets/stylesheets/covered.scss"'))

    assert_equal :inconclusive, result.outcome, "a partial map must not read as green or as red"
    assert_includes tool.uncovered.map { |p| File.basename(p) }, "orphan.scss"
  end

  def test_unreadable_map_is_inconclusive_never_green
    result, = run_tool(File.join(@repo, "MASTER", "checks", "data", "absent.yml"))

    assert_equal :inconclusive, result.outcome
  end
end
