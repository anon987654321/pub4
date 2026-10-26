# frozen_string_literal: true

require "minitest/autorun"
require "tmpdir"
require "fileutils"
require "stringio"
require_relative "../tools/diff_routes"

# Every coordinate form PATH_OWNERSHIP.yml actually uses gets a row here:
# exact file, directory prefix, shell glob, the ../ sibling form, the
# RAILS/master/ form, MASTER/ stripping for diff output, and specificity
# (lib/cognition/ over lib/). The gap case is asserted as a gap, never a
# guess — that is the tool's one honesty promise.
class TestDiffRoutes < Minitest::Test
  OWNERSHIP = {
    "README.md" => { "purpose" => "front door", "risk" => "low", "check" => "bin/check" },
    "lib/" => { "purpose" => "library", "risk" => "medium", "check" => "bin/check" },
    "lib/cognition/" => { "purpose" => "cognition layer", "risk" => "high", "check" => "bin/check --profile=agent" },
    "loop*.gif" => { "purpose" => "loop animation", "risk" => "low", "check" => "bin/check" },
    "../OPENBSD/lib/zshrc.shared" => { "purpose" => "prompt contract", "risk" => "low", "check" => "ruby OPENBSD/test/test_operator_prompt_contract.rb" },
    "RAILS/master/" => { "purpose" => "master face", "risk" => "critical", "check" => "bin/check --profile=web" },
  }.freeze

  def setup
    @dir = Dir.mktmpdir
    @path = File.join(@dir, "PATH_OWNERSHIP.yml")
    File.write(@path, { "ownership" => OWNERSHIP }.to_yaml)
    @io = StringIO.new
  end

  def teardown
    FileUtils.remove_entry(@dir)
  end

  def routes(*paths)
    Deploy::DiffRoutes.run(paths:, ownership_path: @path, repo_root: @dir, io: @io)
    @io.string
  end

  def test_exact_file_row_matches
    out = routes("README.md")

    assert_includes out, "front door"
    assert_includes out, "owner README.md (low)"
  end

  def test_directory_prefix_matches_and_specific_row_wins_over_general
    out = routes("lib/cognition/loop.rb")

    assert_match(%r{owner lib/cognition/ \(high\)}, out)
    assert_match(%r{also  lib/ \(medium\)}, out)
  end

  def test_glob_row_matches
    out = routes("loop3.gif")

    assert_includes out, "loop*.gif"
  end

  def test_sibling_tree_row_matches_through_dotdot
    out = routes("../OPENBSD/lib/zshrc.shared")

    assert_includes out, "prompt contract"
  end

  def test_diff_path_with_master_prefix_is_stripped_before_matching
    out = routes("MASTER/lib/core.rb")

    assert_match(%r{owner lib/ \(medium\)}, out)
  end

  def test_rails_master_row_matches_its_subtree
    out = routes("RAILS/master/public/face.css")

    assert_match(%r{owner RAILS/master/ \(critical\)}, out)
  end

  def test_unowned_path_is_a_gap_and_names_the_file
    gaps = Deploy::DiffRoutes.run(paths: ["no/such/row.rb"], ownership_path: @path, repo_root: @dir, io: @io)

    assert_equal ["no/such/row.rb"], gaps
    assert_includes @io.string, "GAP"
    assert_includes @io.string, "PATH_OWNERSHIP"
  end

  def test_row_without_a_check_says_so_instead_of_inventing_one
    File.write(@path, { "ownership" => { "orphan/" => { "purpose" => "declared, untestable" } } }.to_yaml)
    out = routes("orphan/thing.rb")

    assert_includes out, "no check named"
  end
end
