# frozen_string_literal: true

require_relative "test_helper"

class TestPreserveUserIntent < Minitest::Test
  def setup
    @guard = Master::Ground::PreserveUserIntent.new(root: Master::ROOT)
  end

  def test_allows_non_refactor_commits
    diff = "+def new_method\n"
    result = @guard.assert_preserved!(diff, message: "fix: typo")
    assert result.ok?
  end

  def test_blocks_signature_change_on_refactor
    diff = <<~DIFF
      -def old_name
      +def new_name
    DIFF
    result = @guard.assert_preserved!(diff, message: "refactor: rename method")
    assert result.err?
    assert_includes result.message, "public_method_signature"
  end

  def test_allows_refactor_with_explicit_approval
    diff = "+def new_name\n-def old_name\n"
    result = @guard.assert_preserved!(diff, message: "refactor: rename behavior_change_approved")
    assert result.ok?
  end
end