# frozen_string_literal: true

require_relative "test_helper"
require_relative "../tools/task_map"

class TestTaskMap < Minitest::Test
  def test_task_map_is_rendered_from_the_yaml_source
    rendered = Operator::TaskMap.render
    assert_includes rendered, "Edit HTML content without redesign"
    assert_includes rendered, "MASTER/bin/operator laws ID"
    assert_includes rendered, "rendered-output comparison"
  end

  def test_checked_in_task_map_matches_its_source
    assert Operator::TaskMap.check
  end
end
