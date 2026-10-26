# frozen_string_literal: true

require "minitest/autorun"
require_relative "../__shared/config/test_scope"

# `bin/rails test` and the CI step must agree about what brgen's suite is.
#
# Rails globs test/**/*_test.rb from the app root, which never reaches the
# mountable verticals beside it. Three copies of the widened glob drifted twice:
# 26 engine tests went unrun while CI stayed green, and on 2026-08-10 three
# sessions reported "brgen green" over 349 runs against CI's 381. The scope is
# now one constant, Pub4TestScope, and this asserts both commands read it.
class TestScopeParityTest < Minitest::Test
  ROOT = File.expand_path("..", __dir__)

  def source(*path) = File.read(File.join(ROOT, *path))

  def test_ci_and_brgen_read_the_one_scope
    assert_includes source("__shared", "config", "ci.rb"), "Pub4TestScope::GLOB"
    assert_includes source("__shared", "config", "ci.rb"), "Pub4TestScope::EXCLUDE"
    assert_includes source("brgen", "config", "application.rb"), "Pub4TestScope::GLOB"
    assert_includes source("brgen", "config", "application.rb"), "Pub4TestScope::EXCLUDE"
  end

  # Assert on files, not prose: every vertical with a test directory is reached.
  def test_every_vertical_test_directory_is_in_scope
    Dir.chdir(File.join(ROOT, "brgen")) do
      reached = Dir.glob(Pub4TestScope::GLOB)
                   .reject { |file| File.fnmatch?(Pub4TestScope::EXCLUDE, file, File::FNM_EXTGLOB) }
      verticals = Dir.glob("../brgen_*/**/test/**/*_test.rb").reject { |file| file.match?(%r{/test/(system|dummy|fixtures)/}) }

      assert_empty verticals - reached, "vertical tests outside Pub4TestScope: no command runs them"
      refute_empty reached - Dir.glob("test/**/*_test.rb"), "the scope finds nothing beyond brgen/test; check the glob"
    end
  end
end
