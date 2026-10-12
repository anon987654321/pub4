# frozen_string_literal: true

require_relative "test_helper"
require "operator/branches"

class TestOperatorBranches < Minitest::Test
  def classify(**over)
    Operator::Branches.classify(**{ ahead: 3, age: 7200, deleted: 10, conflicts: false }.merge(over))
  end

  def test_a_branch_with_nothing_ahead_is_merged
    assert_equal :merged, classify(ahead: 0, age: 5)
  end

  def test_a_recent_push_means_an_agent_is_still_working
    assert_equal :active, classify(age: 600, conflicts: true, deleted: 999_999)
  end

  def test_conflicts_come_before_mass_deletion
    assert_equal :conflicts, classify(conflicts: true, deleted: 999_999)
  end

  def test_mass_deletion_is_named_and_ordinary_work_is_ready
    assert_equal :deletes_heavily, classify(deleted: 135_177)
    assert_equal :ready, classify
  end
end
