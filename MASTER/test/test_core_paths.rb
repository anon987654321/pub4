# frozen_string_literal: true

require_relative "test_helper"
require_relative "../lib/core/paths"

class TestCorePaths < Minitest::Test
  def paths
    Master::Core::Paths.new(root: Master::ROOT)
  end

  def test_soul_owns_the_sacred_paths
    assert_includes paths.sacred_paths, "data"
    assert_includes paths.sacred_paths, "data/SOUL.md"
    assert_includes paths.sacred_paths, "data/project_context.yml"
    assert_includes paths.sacred_paths, "lib/review/scan"
    assert_includes paths.sacred_paths, "bin/cli"
  end

  def test_authored_fix_code_is_not_sacred
    refute paths.sacred?("lib/fix/fix_loop.rb")
    refute paths.sacred?("lib/core/paths.rb")
  end

  def test_path_escape_is_treated_as_protected
    assert paths.sacred?("../outside")
  end
end
