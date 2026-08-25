# frozen_string_literal: true

require_relative "../test_helper"
require_relative "../../lib/autonomy"

class TestEventStore < Minitest::Test
  def test_goals_tasks_and_events_survive_reopen
    Dir.mktmpdir do |dir|
      path = File.join(dir, "autonomy.sqlite3")
      goal = Master::Autonomy::Goal.create(objective: "repair tests")
      task = Master::Autonomy::Task.create(goal_id: goal.id, title: "inspect")

      store = Master::Autonomy::EventStore.new(path)
      store.create_goal(goal)
      store.create_task(task)
      store.append(goal.id, task.id, "test", { ok: true })
      store.close

      reopened = Master::Autonomy::EventStore.new(path)
      assert_equal goal.objective, reopened.goal(goal.id)["objective"]
      assert_equal task.title, reopened.tasks(goal.id).first["title"]
      assert_equal "test", reopened.events(goal.id).first["kind"]
      reopened.close
    end
  end
end
