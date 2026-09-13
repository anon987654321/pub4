# frozen_string_literal: true

require_relative "test_helper"

# TypeChecker is the deterministic constraint pass FastStage runs before any
# model sees a file. Only Ruby that parses is checked, and each violation
# carries the complement that repairs it.
class TestGroundTypeChecker < Minitest::Test
  TC = Master::Ground::TypeChecker

  def rules(source, path: "a.rb") = TC.check(path, source).map(&:rule)

  def test_a_bare_rescue_is_flagged_and_a_typed_one_is_not
    bare = "# frozen_string_literal: true\nbegin\n  x\nrescue => e\n  y\nend\n"
    typed = "# frozen_string_literal: true\nbegin\n  x\nrescue StandardError => e\n  y\nend\n"

    assert_equal [:BARE_RESCUE], rules(bare)
    assert_empty rules(typed)
    assert_equal "rescue StandardError", TC.check("a.rb", bare).first.complement
  end

  def test_the_magic_comment_is_required
    assert_equal [:FROZEN_STRING_LITERAL], rules("x = 1\n")
  end

  def test_a_shebang_may_precede_the_magic_comment
    assert_empty rules("#!/usr/bin/env ruby\n# frozen_string_literal: true\nputs 1\n")
  end

  def test_other_languages_and_unparseable_ruby_are_skipped
    assert_empty rules("x = 1\n", path: "a.js")
    assert_empty rules("def (\n")
  end

  def test_a_registered_constraint_joins_the_walk
    checker = TC.new.register(:NO_PUTS) do |node, _src|
      next unless node.is_a?(Prism::CallNode) && node.name == :puts

      { message: "puts", complement: "logger" }
    end

    assert_equal [:NO_PUTS], checker.check("a.rb", "# frozen_string_literal: true\nputs 1\n").map(&:rule)
  end
end
