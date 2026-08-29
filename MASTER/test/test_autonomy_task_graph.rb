# frozen_string_literal: true

require_relative "test_helper"
require_relative "../lib/autonomy"

class TestTaskGraph < Minitest::Test
  def test_parent_dependency_makes_child_wait
    parent = Master::Autonomy::Task.create(goal_id: "g", title: "inspect")
    child = Master::Autonomy::Task.create(goal_id: "g", title: "change", parent_id: parent.id)

    graph = Master::Autonomy::TaskGraph.new([parent, child])

    assert_equal [parent.id], graph.ready.map(&:id)
  end

  def test_cycle_is_rejected
    first = Master::Autonomy::Task.create(goal_id: "g", title: "one")
    second = Master::Autonomy::Task.create(goal_id: "g", title: "two", parent_id: first.id)

    assert_raises(RuntimeError) do
      Master::Autonomy::TaskGraph.new([first.with(parent_id: second.id), second])
    end
  end
end
